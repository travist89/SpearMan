extends Node3D

# Networking
var peer = ENetMultiplayerPeer.new()
@export var player_scene: PackedScene
var spear_scene = preload("res://Spear.tscn")
var enemy_scene = preload("res://Enemy.tscn")
var target_scene = preload("res://Target.tscn")
var collectible_health_scene = preload("res://CollectibleHealth.tscn")
var collectible_speed_scene = preload("res://CollectibleSpeed.tscn")

# Environment
var noise = FastNoiseLite.new()
var terrain_size = 200.0
var terrain_height = 10.0
var terrain_resolution = 100 # Vertices per side

func _ready():
	# Networking Spawner
	var spawner = MultiplayerSpawner.new()
	# Set spawn path to the current node (World)
	# Since spawner is a child, ".." refers to the parent (World).
	# Alternatively, get_path() sets the absolute path to World.
	spawner.spawn_path = get_path()
	spawner.add_spawnable_scene(player_scene.resource_path)
	spawner.add_spawnable_scene(spear_scene.resource_path)
	spawner.add_spawnable_scene(enemy_scene.resource_path)
	spawner.add_spawnable_scene(target_scene.resource_path)
	spawner.add_spawnable_scene(collectible_health_scene.resource_path)
	spawner.add_spawnable_scene(collectible_speed_scene.resource_path)
	add_child(spawner)
	
	# UI for Multiplayer
	create_multiplayer_ui()
	
	# Procedural Generation (Done locally for now, assuming deterministic or just local)
	# In a real game, server would generate and sync, or seed would be synced.
	randomize()
	noise.seed = 12345 # Fixed seed for now so clients match
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	
	setup_environment()

func create_multiplayer_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var vbox = VBoxContainer.new()
	canvas.add_child(vbox)
	vbox.position = Vector2(20, 100)
	
	var host_btn = Button.new()
	host_btn.text = "Host"
	host_btn.pressed.connect(start_host)
	vbox.add_child(host_btn)
	
	var join_btn = Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(start_join)
	vbox.add_child(join_btn)

func start_host():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
		
	peer.create_server(13579)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(add_player)
	add_player(1) # Add host player
	print("Hosting...")

func start_join():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		return

	peer.create_client("127.0.0.1", 13579)
	multiplayer.multiplayer_peer = peer
	print("Joining...")
	# Clean up any existing player (e.g. from previous sessions or testing)
	if has_node("Player"):
		$Player.queue_free()

func add_player(id = 1):
	# Only spawn on server
	if not multiplayer.is_server(): return

	var player = player_scene.instantiate()
	player.name = str(id)
	add_child(player)
	player.position = Vector3(0, 5, 0) # Spawn high
	
	# Clean up existing player from single player setup if exists
	if has_node("Player"):
		$Player.queue_free()

func setup_environment():
	create_terrain() # Run locally on all clients
	
	# Interactive objects spawned only on server
	if multiplayer.is_server():
		scatter_targets(50)
		scatter_enemies(20)
		scatter_collectibles(20)

func create_terrain():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate vertices
	for z in range(terrain_resolution + 1):
		for x in range(terrain_resolution + 1):
			var percent_x = float(x) / terrain_resolution
			var percent_z = float(z) / terrain_resolution
			
			var world_x = (percent_x - 0.5) * terrain_size
			var world_z = (percent_z - 0.5) * terrain_size
			var y = noise.get_noise_2d(world_x, world_z) * terrain_height
			
			# Flatten the center area for the player start
			if abs(world_x) < 10 and abs(world_z) < 10:
				y = lerp(y, 0.0, 0.8)
			
			var u = percent_x
			var v = percent_z
			
			st.set_uv(Vector2(u, v))
			st.set_color(Color(0.3, 0.6 + (y/terrain_height)*0.2, 0.3)) # Vary green based on height
			st.add_vertex(Vector3(world_x, y, world_z))

	# Generate indices
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var vert = z * (terrain_resolution + 1) + x
			# Triangle 1
			st.add_index(vert)
			st.add_index(vert + 1)
			st.add_index(vert + terrain_resolution + 1)
			# Triangle 2
			st.add_index(vert + 1)
			st.add_index(vert + terrain_resolution + 2)
			st.add_index(vert + terrain_resolution + 1)

	st.generate_normals()
	var mesh = st.commit()
	
	# Create StaticBody for terrain
	var terrain = StaticBody3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true # Use the colors set in SurfaceTool
	mesh_inst.material_override = mat
	terrain.add_child(mesh_inst)
	
	# Collision
	var shape = mesh.create_trimesh_shape()
	var col = CollisionShape3D.new()
	col.shape = shape
	terrain.add_child(col)

func scatter_targets(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		var z = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		
		# Avoid spawn area
		if abs(x) < 5 and abs(z) < 5:
			continue
			
		var y = noise.get_noise_2d(x, z) * terrain_height
		# Adjust height logic same as terrain generation
		if abs(x) < 10 and abs(z) < 10:
			y = lerp(y, 0.0, 0.8)
			
		create_target_at(Vector3(x, y + 1.5, z))

func create_target_at(pos):
	var target = target_scene.instantiate()
	add_child(target) # Spawner handles replication
	target.position = pos
	
	# Face the center
	target.look_at(Vector3(0, pos.y, 0), Vector3.UP)
	# Additional rotation handled in Scene or here?
	# Scene has Cylinder oriented Y-up.
	# Original code rotated 90 deg X to make it face player.
	target.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

func scatter_enemies(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		var z = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		
		# Avoid spawn area
		if abs(x) < 15 and abs(z) < 15:
			continue
			
		var y = noise.get_noise_2d(x, z) * terrain_height
		if abs(x) < 10 and abs(z) < 10:
			y = lerp(y, 0.0, 0.8)
			
		create_enemy_at(Vector3(x, y + 1.0, z))

func create_enemy_at(pos):
	var enemy = enemy_scene.instantiate()
	add_child(enemy)
	enemy.position = pos

func scatter_collectibles(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		var z = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		
		var y = noise.get_noise_2d(x, z) * terrain_height
		if abs(x) < 10 and abs(z) < 10:
			y = lerp(y, 0.0, 0.8)
			
		var type = "health" if i % 2 == 0 else "speed"
		create_collectible_at(Vector3(x, y + 1.0, z), type)

func create_collectible_at(pos, type):
	var item
	if type == "speed":
		item = collectible_speed_scene.instantiate()
	else:
		item = collectible_health_scene.instantiate()
		
	add_child(item)
	item.position = pos
