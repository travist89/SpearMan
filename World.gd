# World Controller for "Age of Manwe"
# This script is the "Brain" of the game. It handles:
# 1. Networking (Hosting and Joining)
# 2. Procedural Terrain Generation (using Noise)
# 3. Spawning players, enemies, and items
# 4. Day/Night Cycle
extends Node3D

# --- Networking Setup ---
# ENetMultiplayerPeer is the engine's built-in networking tool
var peer = ENetMultiplayerPeer.new()

# @export PackedScenes are references to the .tscn files (prefabs) 
# that we want to create during the game.
@export var player_scene: PackedScene
@export var spear_scene: PackedScene = preload("res://Spear.tscn")
@export var rock_scene: PackedScene = preload("res://Rock.tscn")
@export var enemy_scene: PackedScene = preload("res://Enemy.tscn")
@export var mammoth_scene: PackedScene = preload("res://Mammoth.tscn")
@export var target_scene: PackedScene = preload("res://Target.tscn")
@export var collectible_health_scene: PackedScene = preload("res://CollectibleHealth.tscn")
@export var collectible_speed_scene: PackedScene = preload("res://CollectibleSpeed.tscn")

# --- Environment Variables ---
var noise = FastNoiseLite.new() # Used to generate random-looking but smooth terrain
var terrain_size = 250.0 
var terrain_height = 6.0 
var terrain_resolution = 120 
var lake_level = 0.0 

# --- Day/Night Cycle Variables ---
var time = 0.0
var day_duration = 120.0 
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment

# MultiplayerSpawner is a powerful Godot node that automatically creates
# objects on all clients when they are created on the server.
var spawner: MultiplayerSpawner
var spawn_id_counter = 0

func _ready():
	# --- Setup Multiplayer Spawner ---
	spawner = MultiplayerSpawner.new()
	spawner.name = "MultiplayerSpawner" 
	spawner.spawn_path = get_path() # Objects will be added as children of World
	
	# The spawn_function is called whenever we want to spawn something networked.
	# It ensures the object is initialized correctly on all machines.
	spawner.spawn_function = _spawn_node
	
	# Register which scenes are allowed to be spawned across the network
	spawner.add_spawnable_scene(player_scene.resource_path)
	spawner.add_spawnable_scene(spear_scene.resource_path)
	spawner.add_spawnable_scene(rock_scene.resource_path)
	spawner.add_spawnable_scene(enemy_scene.resource_path)
	spawner.add_spawnable_scene(mammoth_scene.resource_path)
	spawner.add_spawnable_scene(target_scene.resource_path)
	spawner.add_spawnable_scene(collectible_health_scene.resource_path)
	spawner.add_spawnable_scene(collectible_speed_scene.resource_path)
	add_child(spawner)
	
	create_multiplayer_ui()
	setup_lighting_and_sky()
	
	# --- Procedural Generation Setup ---
	# Using a fixed seed ensures every player sees the EXACT same terrain
	seed(12345)
	noise.seed = 12345 
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.012
	
	# Generate terrain (this runs on everyone's computer)
	create_terrain() 
	create_mustard_lakes()
	
	# Scatter static trees and rocks (deterministic, so everyone sees them in the same spot)
	scatter_pretzel_trees(60)
	scatter_crouton_rocks(40)
	
	# --- Server-Only Initialization ---
	# We moved the initial spawn logic to start_host() because
	# multiplayer.is_server() is false here when running as a listen server (host).

func _process(delta):
	# Update the sun and moon position every frame
	update_day_night_cycle(delta)

# Sets up the sky colors and sun/moon lights
func setup_lighting_and_sky():
	if has_node("WorldEnvironment"):
		world_env = $WorldEnvironment
	else:
		world_env = WorldEnvironment.new()
		add_child(world_env)
		
	# Create a procedural sky if one doesn't exist
	if world_env.environment == null:
		var env = Environment.new()
		var sky = Sky.new()
		var sky_mat = ProceduralSkyMaterial.new()
		sky.sky_material = sky_mat
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		world_env.environment = env

	# Find or create the Sun
	if has_node("DirectionalLight3D"):
		sun = $DirectionalLight3D
	else:
		sun = DirectionalLight3D.new(); sun.name = "Sun"
		sun.shadow_enabled = true; add_child(sun)
		
	# Find or create the Moon
	if has_node("Moon"):
		moon = $Moon
	else:
		moon = DirectionalLight3D.new(); moon.name = "Moon"
		moon.shadow_enabled = true; add_child(moon)

# Rotates the sun and moon to create a day/night cycle
func update_day_night_cycle(delta):
	time += delta
	var progress = fmod(time / day_duration, 1.0)
	var angle = progress * TAU - (PI / 2) # TAU is 2*PI
	sun.rotation.x = angle
	moon.rotation.x = angle + PI # Moon is opposite of the sun
	
	# Change light intensity based on height (dark at night)
	var sun_height = sin(angle)
	sun.light_energy = clamp(sun_height * 2.0, 0.0, 1.2)
	moon.light_energy = clamp(-sun_height * 2.0, 0.0, 0.7)

# UI for Connecting and Spawning
var connection_ui: Control
var spawn_ui: Control

func create_multiplayer_ui():
	var canvas = CanvasLayer.new(); add_child(canvas)
	
	# Initial menu for Hosting/Joining
	connection_ui = VBoxContainer.new()
	canvas.add_child(connection_ui)
	connection_ui.position = Vector2(20, 100)
	var host_btn = Button.new(); host_btn.text = "Host Game"
	host_btn.pressed.connect(start_host); connection_ui.add_child(host_btn)
	var join_btn = Button.new(); join_btn.text = "Join Game"
	join_btn.pressed.connect(start_join); connection_ui.add_child(join_btn)
	
	# Menu for choosing where to spawn
	spawn_ui = VBoxContainer.new()
	canvas.add_child(spawn_ui)
	spawn_ui.position = Vector2(20, 100)
	spawn_ui.visible = false
	
	var label = Label.new(); label.text = "Choose Spawn Point:"; spawn_ui.add_child(label)
	var cave_btn = Button.new(); cave_btn.text = "Cave (North West)"
	cave_btn.pressed.connect(func(): request_spawn_at.rpc_id(1, 0)); spawn_ui.add_child(cave_btn)
	var jungle_btn = Button.new(); jungle_btn.text = "Jungle (South East)"
	jungle_btn.pressed.connect(func(): request_spawn_at.rpc_id(1, 1)); spawn_ui.add_child(jungle_btn)
	var altar_btn = Button.new(); altar_btn.text = "Altar (Center)"
	altar_btn.pressed.connect(func(): request_spawn_at.rpc_id(1, 2)); spawn_ui.add_child(altar_btn)

# Server starts hosting
func start_host():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED: return
	peer.create_server(13579) # Port number
	multiplayer.multiplayer_peer = peer
	
	connection_ui.visible = false
	spawn_ui.visible = true
	
	# Spawn initial enemies and items now that the server is active
	if multiplayer.is_server():
		scatter_targets(30)
		scatter_enemies(12, 5)
		scatter_mammoths(3)
		scatter_collectibles(20)

# Client joins a host
func start_join():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED: return
	peer.create_client("127.0.0.1", 13579) # Connect to localhost
	multiplayer.multiplayer_peer = peer
	
	connection_ui.visible = false
	spawn_ui.visible = true

# Clients call this RPC on the server to request to spawn at a specific location
@rpc("any_peer", "call_local")
func request_spawn_at(location_index):
	var sender_id = multiplayer.get_remote_sender_id()
	# Only the server can actually spawn nodes
	if multiplayer.is_server():
		add_player(sender_id, location_index)
		# Tell the client to hide their spawn menu
		if sender_id == 1: spawn_ui.visible = false
		else: hide_spawn_ui_on_client.rpc_id(sender_id)

@rpc("authority", "call_remote")
func hide_spawn_ui_on_client():
	spawn_ui.visible = false

# The Server calls this to initiate a player spawn through the MultiplayerSpawner
func add_player(id = 1, location_index = 2):
	if not multiplayer.is_server(): return
	# This triggers _spawn_node on ALL peers
	spawner.spawn({"id": id, "location_index": location_index})

# --- CENTRAL SPAWN DISPATCHER ---
# This function is called by the MultiplayerSpawner on ALL machines when spawner.spawn() 
# is called on the server. This is the "Magic" that syncs object creation!
func _spawn_node(data):
	if data.has("id"):
		return _spawn_player_impl(data)
	elif data.has("type"):
		var type = data["type"]
		if type == "mammoth": return _spawn_mammoth(data)
		elif type == "target": return _spawn_target(data)
		elif type == "collectible_health": return _spawn_collectible(data, collectible_health_scene)
		elif type == "collectible_speed": return _spawn_collectible(data, collectible_speed_scene)
	elif data.has("pos"):
		return _spawn_enemy(data)
	return null

# Logic to create a player node and position it
func _spawn_player_impl(data):
	var id = data["id"]
	var location_index = data["location_index"]
	
	var player = player_scene.instantiate()
	player.name = str(id) # Important: Node name must be the Peer ID!
	
	# Determine spawn position based on choice
	var spawn_pos = Vector3.ZERO
	if location_index == 0: spawn_pos = Vector3(-50, 5, -50) # Cave
	elif location_index == 1: spawn_pos = Vector3(50, 5, 50) # Jungle
	else: spawn_pos = Vector3(0, 5, 0) # Altar
	
	player.position = spawn_pos
	return player

# Logic to create an AI enemy
func _spawn_enemy(data):
	var pos = data["pos"]
	var is_big = data["is_big"]
	var spawn_id = data["spawn_id"]
	
	var enemy = enemy_scene.instantiate()
	enemy.name = "Enemy_" + str(spawn_id) # Unique name
	enemy.position = pos
	enemy.is_big = is_big
	return enemy

# Logic to create a Mammoth
func _spawn_mammoth(data):
	var pos = data["pos"]
	var spawn_id = data["spawn_id"]
	
	var mammoth = mammoth_scene.instantiate()
	mammoth.name = "Mammoth_" + str(spawn_id)
	mammoth.position = pos
	return mammoth

func _spawn_target(data):
	var pos = data["pos"]
	var spawn_id = data["spawn_id"]
	var target = target_scene.instantiate()
	target.name = "Target_" + str(spawn_id)
	target.position = pos
	return target

func _spawn_collectible(data, scene):
	var pos = data["pos"]
	var spawn_id = data["spawn_id"]
	var item = scene.instantiate()
	item.name = "Collectible_" + str(spawn_id)
	item.position = pos
	return item

# --- TERRAIN GENERATION LOGIC ---
# Uses a SurfaceTool to build a 3D mesh from scratch using Noise values
func create_terrain():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for z in range(terrain_resolution + 1):
		for x in range(terrain_resolution + 1):
			var px = float(x) / terrain_resolution
			var pz = float(z) / terrain_resolution
			var wx = (px - 0.5) * terrain_size
			var wz = (pz - 0.5) * terrain_size
			
			# Get height from noise
			var y = noise.get_noise_2d(wx, wz) * terrain_height
			# Flatten the center area for the spawn altar
			if abs(wx) < 15 and abs(wz) < 15: y = lerp(y, 3.0, 0.95) 
			
			# Pick a color based on height (Sand at low, Grass at medium, Rock at high)
			var color = Color(0.2, 0.45, 0.1) 
			if y < lake_level + 1.0: color = Color(0.95, 0.85, 0.3) # Sand
			
			st.set_color(color)
			st.add_vertex(Vector3(wx, y, wz))
			
	# Connect the vertices into triangles
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var v = z * (terrain_resolution + 1) + x
			st.add_index(v); st.add_index(v + 1); st.add_index(v + terrain_resolution + 1)
			st.add_index(v + 1); st.add_index(v + terrain_resolution + 2); st.add_index(v + terrain_resolution + 1)
			
	st.generate_normals()
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh_inst.material_override = mat
	
	var terrain = StaticBody3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.add_child(mesh_inst)
	
	# Create a collision shape so players don't fall through the floor
	var col = CollisionShape3D.new()
	col.shape = mesh_inst.mesh.create_trimesh_shape()
	terrain.add_child(col)

# Creates simple flat water (Mustard Lakes)
func create_mustard_lakes():
	var lake_inst = MeshInstance3D.new(); lake_inst.name = "MustardLake"
	var lake_mesh = PlaneMesh.new(); lake_mesh.size = Vector2(terrain_size, terrain_size)
	lake_inst.mesh = lake_mesh; lake_inst.position.y = lake_level
	add_child(lake_inst)

# --- ENVIRONMENT SCATTERING ---
# These functions place trees, rocks, and enemies across the world

func scatter_pretzel_trees(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2)
		var z = randf_range(-terrain_size/2, terrain_size/2)
		var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0: continue # Don't put trees in the water
		create_pretzel_tree_at(Vector3(x, y, z))

func create_pretzel_tree_at(pos):
	var tree = Node3D.new(); tree.name = "PretzelTree"; add_child(tree); tree.position = pos
	# Simple cylinder for the trunk
	var trunk = MeshInstance3D.new(); trunk.mesh = CylinderMesh.new(); trunk.mesh.height = 3.0
	trunk.position.y = 1.5; tree.add_child(trunk)

func scatter_crouton_rocks(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2)
		var z = randf_range(-terrain_size/2, terrain_size/2)
		var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0: continue
		var rock = MeshInstance3D.new(); rock.mesh = BoxMesh.new(); add_child(rock)
		rock.position = Vector3(x, y, z)

func scatter_targets(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2)
		var z = randf_range(-terrain_size/2, terrain_size/2)
		var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0: continue
		
		spawn_id_counter += 1
		spawner.spawn({"pos": Vector3(x, y + 1.5, z), "type": "target", "spawn_id": spawn_id_counter})

func scatter_enemies(small_count, big_count):
	for i in range(small_count):
		var pos = find_random_spawn_pos()
		if pos != Vector3.ZERO: create_enemy_at(pos, false)
	for i in range(big_count):
		var pos = find_random_spawn_pos()
		if pos != Vector3.ZERO: create_enemy_at(pos, true)

func create_enemy_at(pos, is_big):
	spawn_id_counter += 1
	spawner.spawn({"pos": pos, "is_big": is_big, "spawn_id": spawn_id_counter})

func scatter_mammoths(count):
	for i in range(count):
		var pos = find_random_spawn_pos()
		if pos != Vector3.ZERO: create_mammoth_at(pos)

func create_mammoth_at(pos):
	spawn_id_counter += 1
	spawner.spawn({"pos": pos, "type": "mammoth", "spawn_id": spawn_id_counter})

# --- DYNAMIC SPAWNING ---
var spawn_timer = 0.0
var spawn_interval = 2.0 
var max_enemies = 50 

func _physics_process(delta):
	# Only the server spawns new enemies during gameplay
	if multiplayer.is_server():
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			try_spawn_random_enemy()

func try_spawn_random_enemy():
	var current_enemies = 0
	for child in get_children():
		if "Enemy" in child.name or "Mammoth" in child.name:
			current_enemies += 1
			
	if current_enemies < max_enemies:
		var pos = find_random_spawn_pos()
		if pos != Vector3.ZERO:
			if randf() < 0.2: create_mammoth_at(pos)
			else: create_enemy_at(pos, randf() < 0.3)

func find_random_spawn_pos():
	var x = randf_range(-terrain_size/2, terrain_size/2)
	var z = randf_range(-terrain_size/2, terrain_size/2)
	var y = noise.get_noise_2d(x, z) * terrain_height
	if y > lake_level + 1.0: return Vector3(x, y + 2.0, z)
	return Vector3.ZERO

func scatter_collectibles(count):
	for i in range(count):
		var pos = find_random_spawn_pos()
		if pos != Vector3.ZERO:
			var type = "collectible_speed" if randf() < 0.5 else "collectible_health"
			spawn_id_counter += 1
			spawner.spawn({"pos": pos, "type": type, "spawn_id": spawn_id_counter})
