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
@export var fire_spear_scene: PackedScene = preload("res://FireSpear.tscn")
@export var rock_scene: PackedScene = preload("res://Rock.tscn")
@export var mammoth_scene: PackedScene = preload("res://Mammoth.tscn")
@export var target_scene: PackedScene = preload("res://Target.tscn")
@export var collectible_health_scene: PackedScene = preload("res://CollectibleHealth.tscn")
@export var collectible_speed_scene: PackedScene = preload("res://CollectibleSpeed.tscn")
@export var grass_patch_scene: PackedScene = preload("res://GrassPatch.tscn")

# --- Environment Variables ---
var noise = FastNoiseLite.new() # Used to generate random-looking but smooth terrain
var terrain_size = 800.0 
var terrain_height = 40.0 
var terrain_resolution = 300 
var lake_level = 0.0 
var current_seed = 0

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
	# FIX: spawn_path must point to the World node ("..") so spawned objects become
	# direct children of World (siblings of the spawner). 
	# This is critical because World.gd logic (like counting enemies) iterates over get_children().
	# If spawn_path was "." (default), enemies would be children of the Spawner, breaking the count logic
	# and causing infinite spawning loops and network floods.
	spawner.spawn_path = ".." 
	
	# The spawn_function is called whenever we want to spawn something networked.
	# It ensures the object is initialized correctly on all machines.
	spawner.spawn_function = _spawn_node
	
	# Register which scenes are allowed to be spawned across the network
	spawner.add_spawnable_scene(player_scene.resource_path)
	spawner.add_spawnable_scene(spear_scene.resource_path)
	spawner.add_spawnable_scene(fire_spear_scene.resource_path)
	spawner.add_spawnable_scene(rock_scene.resource_path)
	spawner.add_spawnable_scene(mammoth_scene.resource_path)
	spawner.add_spawnable_scene(target_scene.resource_path)
	spawner.add_spawnable_scene(collectible_health_scene.resource_path)
	spawner.add_spawnable_scene(collectible_speed_scene.resource_path)
	spawner.add_spawnable_scene(grass_patch_scene.resource_path)
	add_child(spawner)
	
	create_multiplayer_ui()
	setup_lighting_and_sky()
	
	# --- Procedural Generation Setup ---
	# We set these properties here, but the SEED is set later in initialize_world()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.003 # Even lower frequency for wider, smoother mountains
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3 # Less octaves for smoother, less jagged mountains
	
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
var seed_ui: Control
var seed_input: LineEdit
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
	
	# Menu for Seed Entry
	seed_ui = VBoxContainer.new()
	canvas.add_child(seed_ui)
	seed_ui.position = Vector2(20, 100)
	seed_ui.visible = false
	
	var seed_label = Label.new(); seed_label.text = "Enter Seed Word:"; seed_ui.add_child(seed_label)
	seed_input = LineEdit.new(); seed_input.placeholder_text = "Type seed here..."; seed_ui.add_child(seed_input)
	var start_game_btn = Button.new(); start_game_btn.text = "Start Game"
	start_game_btn.pressed.connect(start_game_with_seed); seed_ui.add_child(start_game_btn)
	
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
	
	# Connect peer connected signal to send seed to new players
	multiplayer.peer_connected.connect(_on_peer_connected)
	
	connection_ui.visible = false
	seed_ui.visible = true

func start_game_with_seed():
	var seed_text = seed_input.text
	if seed_text == "": seed_text = str(randi()) # Default random seed if empty
	
	# Convert string seed to integer
	current_seed = seed_text.hash()
	
	seed_ui.visible = false
	spawn_ui.visible = true
	
	# Generate world
	initialize_world(current_seed)
	
	# Since we are host, we initialize game objects
	if multiplayer.is_server():
		scatter_targets(60)
		scatter_mammoths(40)
		scatter_collectibles(80)
		spawn_dense_grass()

# Client joins a host
func start_join():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED: return
	peer.create_client("127.0.0.1", 13579) # Connect to localhost
	multiplayer.multiplayer_peer = peer
	
	connection_ui.visible = false
	# Wait for seed from server before showing spawn UI

func _on_peer_connected(id):
	# Send current seed to the new player
	receive_seed.rpc_id(id, current_seed)

@rpc("authority", "call_remote", "reliable")
func receive_seed(seed_val):
	current_seed = seed_val
	initialize_world(current_seed)
	spawn_ui.visible = true

func initialize_world(seed_val):
	seed(seed_val)
	noise.seed = seed_val
	
	# Clear old terrain if any (though usually runs once)
	if has_node("Terrain"):
		$Terrain.queue_free()
	if has_node("MustardLake"):
		$MustardLake.queue_free()
		
	# Generate terrain (this runs on everyone's computer)
	create_terrain() 
	create_mustard_lakes()
	
	# Scatter static trees and rocks (deterministic, so everyone sees them in the same spot)
	scatter_pretzel_trees(150)
	scatter_crouton_rocks(100)

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
	var player_node = spawner.spawn({"id": id, "location_index": location_index})
	
	# Explicitly set authority to the player
	# This ensures the client controls their own player object
	# We use the returned node from spawn() which is safer than get_node() immediately
	if player_node:
		player_node.set_multiplayer_authority(id)

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
		elif type == "grass_patch": return _spawn_grass(data)
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

# Centralized height function to ensure terrain mesh and object placement match exactly
func get_height_at(wx, wz):
	var noise_val = noise.get_noise_2d(wx, wz)
	
	# Use a smoother curve: Preserve lowlands, raise highlands gently
	var y = noise_val * 25.0 
	
	# Slight exaggeration for peaks, but less extreme
	if y > 10.0:
		y += (y - 10.0) * 0.5
	
	# Flatten the center area for the spawn altar
	if abs(wx) < 20 and abs(wz) < 20: y = lerp(y, 3.0, 0.9) 
	
	# --- World Borders (Walls) ---
	var dist_x = abs(wx) / (terrain_size / 2.0)
	var dist_z = abs(wz) / (terrain_size / 2.0)
	var dist_edge = max(dist_x, dist_z)
	
	if dist_edge > 0.9:
		var wall_height = (dist_edge - 0.9) * 10.0 * 50.0 
		y += wall_height
		
	return y

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
			
			var y = get_height_at(wx, wz)
			
			# Pick a color based on height
			var color = Color(0.2, 0.45, 0.1) # Grass
			if y < lake_level + 2.0: color = Color(0.95, 0.85, 0.3) # Sand
			elif y > 25.0: color = Color(0.5, 0.5, 0.5) # Rock/Snow high up
			
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
	
	var lake_mat = StandardMaterial3D.new()
	lake_mat.albedo_color = Color(1.0, 0.9, 0.2) # Yellow water
	lake_mat.roughness = 0.1
	lake_mat.metallic = 0.3
	lake_mesh.material = lake_mat
	
	lake_inst.mesh = lake_mesh; lake_inst.position.y = lake_level
	add_child(lake_inst)

# --- ENVIRONMENT SCATTERING ---
# These functions place trees, rocks, and enemies across the world

func scatter_pretzel_trees(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2)
		var z = randf_range(-terrain_size/2, terrain_size/2)
		var y = get_height_at(x, z)
		if y < lake_level + 1.0: continue # Don't put trees in the water
		create_pretzel_tree_at(Vector3(x, y, z))

func create_pretzel_tree_at(pos):
	var tree = StaticBody3D.new(); tree.name = "PretzelTree"; add_child(tree); tree.position = pos
	
	# Create a brown material for the pretzel tree
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.4, 0.2) # Pretzel brown
	mat.roughness = 0.8
	
	# Simple cylinder for the trunk
	var trunk_mesh = CylinderMesh.new()
	trunk_mesh.height = 3.0
	
	var trunk = MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = mat
	trunk.position.y = 1.5
	tree.add_child(trunk)
	
	# Collision for the trunk
	var col = CollisionShape3D.new()
	col.shape = trunk_mesh.create_trimesh_shape()
	col.position.y = 1.5
	tree.add_child(col)
	
	# Add some twisted branches to make it look like a pretzel
	for i in range(3):
		var branch = MeshInstance3D.new()
		branch.mesh = CylinderMesh.new()
		branch.mesh.top_radius = 0.3
		branch.mesh.bottom_radius = 0.4
		branch.mesh.height = 2.0
		branch.material_override = mat
		
		branch.position.y = 2.5
		branch.rotation.z = deg_to_rad(45 + (i * 120))
		branch.rotation.y = deg_to_rad(i * 120)
		tree.add_child(branch)
		
		# Collision for branches
		var branch_col = CollisionShape3D.new()
		branch_col.shape = branch.mesh.create_trimesh_shape()
		branch_col.position = branch.position
		branch_col.rotation = branch.rotation
		tree.add_child(branch_col)

func scatter_crouton_rocks(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2)
		var z = randf_range(-terrain_size/2, terrain_size/2)
		var y = get_height_at(x, z)
		if y < lake_level + 1.0: continue
		
		var rock = MeshInstance3D.new(); rock.name = "CroutonRock"; add_child(rock)
		
		# Make it look like a crouton (toasted cube)
		var mesh = BoxMesh.new()
		# Slightly random size
		var size = randf_range(0.8, 1.2)
		mesh.size = Vector3(size, size, size)
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.65, 0.3) # Toasted bread color
		mat.roughness = 1.0 # Very rough like bread
		
		rock.mesh = mesh
		rock.material_override = mat
		
		# Random rotation for more natural "tossed" look
		rock.rotation = Vector3(randf()*TAU, randf()*TAU, randf()*TAU)
		# Embed slightly in ground
		rock.position = Vector3(x, y + size * 0.4, z)

func scatter_targets(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2)
		var z = randf_range(-terrain_size/2, terrain_size/2)
		var y = get_height_at(x, z)
		if y < lake_level + 1.0: continue
		
		spawn_id_counter += 1
		spawner.spawn({"pos": Vector3(x, y + 1.5, z), "type": "target", "spawn_id": spawn_id_counter})

func scatter_mammoths(count):
	for i in range(count):
		var pos = find_random_spawn_pos()
		if pos != Vector3.ZERO: create_mammoth_at(pos)

func create_mammoth_at(pos):
	spawn_id_counter += 1
	spawner.spawn({"pos": pos, "type": "mammoth", "spawn_id": spawn_id_counter})

func spawn_dense_grass():
	# Iterate through the terrain grid to place grass densely
	# We use a second noise layer to create "clusters" or "patches" of grass
	var grass_noise = FastNoiseLite.new()
	grass_noise.seed = noise.seed + 100 # Different seed for vegetation pattern
	grass_noise.frequency = 0.05 # Higher frequency = smaller, more frequent clusters
	grass_noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	var step = 4 # Reduced density (was 1) to prevent spawning tens of thousands of grass nodes
	for z in range(0, terrain_resolution + 1, step):
		for x in range(0, terrain_resolution + 1, step):
			var px = float(x) / terrain_resolution
			var pz = float(z) / terrain_resolution
			var wx = (px - 0.5) * terrain_size
			var wz = (pz - 0.5) * terrain_size
			
			# Check if we are inside a grass cluster
			var cluster_value = grass_noise.get_noise_2d(wx, wz)
			if cluster_value < 0.6: continue # Stricter threshold (was 0.4) to spawn fewer patches
			
			# Add some randomness to position so it doesn't look like a perfect grid
			var jitter_x = randf_range(-0.4, 0.4)
			var jitter_z = randf_range(-0.4, 0.4)
			
			# Recalculate world pos with jitter
			var final_wx = wx + jitter_x
			var final_wz = wz + jitter_z
			
			# Get height from unified height function
			var y = get_height_at(final_wx, final_wz)
			
			# Only spawn above water level
			if y > lake_level + 0.5:
				spawn_id_counter += 1
				spawner.spawn({"pos": Vector3(final_wx, y, final_wz), "type": "grass_patch", "spawn_id": spawn_id_counter})

func create_grass_at(pos):
	spawn_id_counter += 1
	spawner.spawn({"pos": pos, "type": "grass_patch", "spawn_id": spawn_id_counter})

func _spawn_grass(data):
	var pos = data["pos"]
	var spawn_id = data["spawn_id"]
	var grass = grass_patch_scene.instantiate()
	grass.name = "GrassPatch_" + str(spawn_id)
	grass.position = pos
	return grass

# --- DYNAMIC SPAWNING ---
var spawn_timer = 0.0
var spawn_interval = 2.0 
var max_enemies = 50 

func _physics_process(delta):
	# Check if multiplayer peer is valid before checking server status
	# If there is no peer, we are not in a multiplayer session
	if not multiplayer.has_multiplayer_peer():
		return
		
	# Check connection status explicitly
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return

	# Only the server spawns new enemies during gameplay
	if multiplayer.is_server():
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			try_spawn_random_enemy()

func try_spawn_random_enemy():
	var current_enemies = 0
	for child in get_children():
		if "Mammoth" in child.name:
			current_enemies += 1
			
	if current_enemies < max_enemies:
		var pos = find_random_spawn_pos()
		if pos != Vector3.ZERO:
			create_mammoth_at(pos)

func find_random_spawn_pos():
	var x = randf_range(-terrain_size/2, terrain_size/2)
	var z = randf_range(-terrain_size/2, terrain_size/2)
	var y = get_height_at(x, z)
	if y > lake_level + 1.0: return Vector3(x, y + 2.0, z)
	return Vector3.ZERO

func find_ground_spawn_pos():
	var x = randf_range(-terrain_size/2, terrain_size/2)
	var z = randf_range(-terrain_size/2, terrain_size/2)
	var y = get_height_at(x, z)
	# Spawn exactly on the ground, but only if above water level
	if y > lake_level + 0.5: return Vector3(x, y, z)
	return Vector3.ZERO

func scatter_collectibles(count):
	for i in range(count):
		var pos = find_ground_spawn_pos()
		if pos != Vector3.ZERO:
			# Favor health collectibles (80% chance) as requested
			var type = "collectible_health" if randf() < 0.8 else "collectible_speed"
			spawn_id_counter += 1
			spawner.spawn({"pos": pos, "type": type, "spawn_id": spawn_id_counter})
