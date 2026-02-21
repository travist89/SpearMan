extends Node3D

# Networking
var peer = ENetMultiplayerPeer.new()
@export var player_scene: PackedScene
var spear_scene = preload("res://Spear.tscn")
var rock_scene = preload("res://Rock.tscn")
var enemy_scene = preload("res://Enemy.tscn")
var target_scene = preload("res://Target.tscn")
var collectible_health_scene = preload("res://CollectibleHealth.tscn")
var collectible_speed_scene = preload("res://CollectibleSpeed.tscn")

# Environment
var noise = FastNoiseLite.new()
var terrain_size = 250.0 
var terrain_height = 20.0 
var terrain_resolution = 120 
var lake_level = 0.0 

# Day/Night Cycle
var time = 0.0
var day_duration = 120.0 
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment

func _ready():
	var spawner = MultiplayerSpawner.new()
	spawner.spawn_path = get_path()
	spawner.add_spawnable_scene(player_scene.resource_path)
	spawner.add_spawnable_scene(spear_scene.resource_path)
	spawner.add_spawnable_scene(rock_scene.resource_path)
	spawner.add_spawnable_scene(enemy_scene.resource_path)
	spawner.add_spawnable_scene(target_scene.resource_path)
	spawner.add_spawnable_scene(collectible_health_scene.resource_path)
	spawner.add_spawnable_scene(collectible_speed_scene.resource_path)
	add_child(spawner)
	
	create_multiplayer_ui()
	setup_lighting_and_sky()
	
	# Use a fixed seed for deterministic generation across all clients
	seed(12345)
	noise.seed = 12345 
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	
	# Only the server generates the environment objects (enemies, collectibles, etc.)
	# The MultiplayerSpawner will replicate these to clients.
	# Terrain and static geometry are generated on all clients deterministically.
	create_terrain() 
	create_mustard_lakes()
	
	# Static environment objects (no networking needed as generation is deterministic)
	scatter_pretzel_trees(60)
	scatter_crouton_rocks(40)
	
	# Networked objects (server authority only)
	if multiplayer.is_server():
		scatter_targets(30)
		scatter_enemies(12, 5)
		scatter_collectibles(20)

func _process(delta):
	update_day_night_cycle(delta)

func setup_lighting_and_sky():
	world_env = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.6, 1.0)
	sky_mat.sky_horizon_color = Color(0.6, 0.5, 0.4)
	sky_mat.ground_bottom_color = Color(0.2, 0.1, 0.1)
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new(); sun.name = "Sun"; sun.shadow_enabled = true
	sun.light_color = Color(1.0, 1.0, 0.85); add_child(sun)
	moon = DirectionalLight3D.new(); moon.name = "Moon"; moon.shadow_enabled = true
	moon.light_color = Color(0.5, 0.65, 1.0); moon.light_energy = 0.6; add_child(moon)

func update_day_night_cycle(delta):
	time += delta
	var progress = fmod(time / day_duration, 1.0)
	var angle = progress * TAU - (PI / 2)
	sun.rotation.x = angle
	moon.rotation.x = angle + PI
	var sun_height = sin(angle)
	sun.light_energy = clamp(sun_height * 2.0, 0.0, 1.2)
	moon.light_energy = clamp(-sun_height * 2.0, 0.0, 0.7)
	var sky_mat = world_env.environment.sky.sky_material
	if sun_height > 0.1: sky_mat.sky_top_color = Color(0.3, 0.5, 0.9)
	elif sun_height > -0.1: sky_mat.sky_top_color = Color(0.8, 0.3, 0.15)
	else: sky_mat.sky_top_color = Color(0.01, 0.01, 0.06)

var connection_ui: Control
var spawn_ui: Control

func create_multiplayer_ui():
	var canvas = CanvasLayer.new(); add_child(canvas)
	
	# Connection Menu
	connection_ui = VBoxContainer.new()
	canvas.add_child(connection_ui)
	connection_ui.position = Vector2(20, 100)
	var host_btn = Button.new(); host_btn.text = "Host"; host_btn.pressed.connect(start_host); connection_ui.add_child(host_btn)
	var join_btn = Button.new(); join_btn.text = "Join"; join_btn.pressed.connect(start_join); connection_ui.add_child(join_btn)
	
	# Spawn Selection Menu (Hidden initially)
	spawn_ui = VBoxContainer.new()
	canvas.add_child(spawn_ui)
	spawn_ui.position = Vector2(20, 100)
	spawn_ui.visible = false
	
	var label = Label.new(); label.text = "Select Spawn Location:"; spawn_ui.add_child(label)
	var cave_btn = Button.new(); cave_btn.text = "Cave (North West)"; cave_btn.pressed.connect(func(): request_spawn_at.rpc_id(1, 0)); spawn_ui.add_child(cave_btn)
	var jungle_btn = Button.new(); jungle_btn.text = "Jungle (South East)"; jungle_btn.pressed.connect(func(): request_spawn_at.rpc_id(1, 1)); spawn_ui.add_child(jungle_btn)
	var altar_btn = Button.new(); altar_btn.text = "Altar (Center)"; altar_btn.pressed.connect(func(): request_spawn_at.rpc_id(1, 2)); spawn_ui.add_child(altar_btn)

func start_host():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED: return
	peer.create_server(13579); multiplayer.multiplayer_peer = peer
	
	# Don't auto-spawn players on connect anymore, wait for them to request spawn
	# multiplayer.peer_connected.connect(add_player) 
	
	# Hide connection buttons, show spawn selection
	connection_ui.visible = false
	spawn_ui.visible = true

func start_join():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED: return
	peer.create_client("127.0.0.1", 13579); multiplayer.multiplayer_peer = peer
	
	# Hide connection buttons, show spawn selection
	connection_ui.visible = false
	spawn_ui.visible = true
	
	if has_node("Player"): $Player.queue_free()

@rpc("any_peer", "call_local")
func request_spawn_at(location_index):
	var sender_id = multiplayer.get_remote_sender_id()
	add_player(sender_id, location_index)
	# Hide spawn UI on the client who requested it (if it was a local call like Host)
	if sender_id == 1:
		spawn_ui.visible = false
	else:
		hide_spawn_ui_on_client.rpc_id(sender_id)

@rpc("authority", "call_remote")
func hide_spawn_ui_on_client():
	spawn_ui.visible = false

func add_player(id = 1, location_index = 2):
	if not multiplayer.is_server(): return
	var player = player_scene.instantiate()
	player.name = str(id)
	
	var spawn_pos = Vector3.ZERO
	if location_index == 0: # Cave
		spawn_pos = Vector3(-50, 0, -50)
	elif location_index == 1: # Jungle
		spawn_pos = Vector3(50, 0, 50)
	else: # Altar
		spawn_pos = Vector3(0, 0, 0)
	
	# Add some randomness to prevent exact stacking if multiple players choose same spot
	spawn_pos.x += randf_range(-2, 2)
	spawn_pos.z += randf_range(-2, 2)
	
	# Calculate terrain height at spawn position
	# Note: noise.get_noise_2d takes world coordinates directly as used in create_terrain
	var y = noise.get_noise_2d(spawn_pos.x, spawn_pos.z) * terrain_height
	
	# Apply the same flattening logic for the center area as in create_terrain
	if abs(spawn_pos.x) < 15 and abs(spawn_pos.z) < 15: 
		y = lerp(y, 3.0, 0.95)
		
	# Set spawn height well above the terrain to avoid getting stuck
	spawn_pos.y = y + 10.0
	
	player.position = spawn_pos
	add_child(player)
	
	if has_node("Player"): $Player.queue_free()

# setup_environment function removed as its logic was moved to _ready

func create_terrain():
	var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(terrain_resolution + 1):
		for x in range(terrain_resolution + 1):
			var px = float(x) / terrain_resolution; var pz = float(z) / terrain_resolution
			var wx = (px - 0.5) * terrain_size; var wz = (pz - 0.5) * terrain_size
			var y = noise.get_noise_2d(wx, wz) * terrain_height
			if abs(wx) < 15 and abs(wz) < 15: y = lerp(y, 3.0, 0.95) 
			var color = Color(0.2, 0.45, 0.1) 
			if y < lake_level + 1.0: color = Color(0.95, 0.85, 0.3) 
			elif y > 10.0: color = Color(0.4, 0.25, 0.1) 
			else: color = Color(0.25, 0.5, 0.15).lerp(Color(0.5, 0.35, 0.1), (y-lake_level)/terrain_height)
			st.set_color(color); st.add_vertex(Vector3(wx, y, wz))
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var v = z * (terrain_resolution + 1) + x
			st.add_index(v); st.add_index(v + 1); st.add_index(v + terrain_resolution + 1)
			st.add_index(v + 1); st.add_index(v + terrain_resolution + 2); st.add_index(v + terrain_resolution + 1)
	st.generate_normals()
	var mesh_inst = MeshInstance3D.new(); mesh_inst.mesh = st.commit()
	var mat = StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true
	mesh_inst.material_override = mat; var terrain = StaticBody3D.new(); terrain.name = "Terrain"
	add_child(terrain); terrain.add_child(mesh_inst)
	var col = CollisionShape3D.new(); col.shape = mesh_inst.mesh.create_trimesh_shape(); terrain.add_child(col)

func create_mustard_lakes():
	var lake_inst = MeshInstance3D.new(); var lake_mesh = PlaneMesh.new(); lake_mesh.size = Vector2(terrain_size, terrain_size); lake_inst.mesh = lake_mesh; lake_inst.position.y = lake_level
	var mat = StandardMaterial3D.new(); mat.albedo_color = Color(1.0, 0.9, 0.0); mat.roughness = 0.05; mat.emission_enabled = true; mat.emission = Color(0.4, 0.3, 0); lake_inst.material_override = mat; add_child(lake_inst)

func scatter_pretzel_trees(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0 or (abs(x) < 20 and abs(z) < 20): continue
		create_pretzel_tree_at(Vector3(x, y, z))

func create_pretzel_tree_at(pos):
	var tree = Node3D.new(); tree.name = "PretzelTree"; add_child(tree); tree.position = pos
	var trunk = MeshInstance3D.new(); trunk.mesh = CylinderMesh.new(); trunk.mesh.top_radius = 0.2; trunk.mesh.bottom_radius = 0.3; trunk.mesh.height = 3.0; trunk.material_override = StandardMaterial3D.new(); trunk.material_override.albedo_color = Color(0.45, 0.25, 0.1); trunk.position.y = 1.5; tree.add_child(trunk)
	for i in range(3):
		var loop = MeshInstance3D.new(); loop.mesh = TorusMesh.new(); loop.mesh.inner_radius = 0.4; loop.mesh.outer_radius = 0.8; loop.material_override = trunk.material_override; loop.position.y = 2.5 + (i * 0.6); loop.rotation = Vector3(randf(), randf(), randf()) * PI; tree.add_child(loop)
		for j in range(4):
			var salt = MeshInstance3D.new(); salt.mesh = BoxMesh.new(); salt.mesh.size = Vector3(0.12, 0.12, 0.12); salt.material_override = StandardMaterial3D.new(); salt.material_override.albedo_color = Color(1,1,1); var a = randf()*TAU; salt.position = Vector3(cos(a)*0.7, 0, sin(a)*0.7); loop.add_child(salt)

func scatter_crouton_rocks(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0: continue
		create_crouton_rock_at(Vector3(x, y, z))

func create_crouton_rock_at(pos):
	var rock = MeshInstance3D.new(); rock.mesh = BoxMesh.new(); rock.mesh.size = Vector3(randf_range(2, 5), randf_range(1, 4), randf_range(2, 5))
	rock.material_override = StandardMaterial3D.new(); rock.material_override.albedo_color = Color(0.85, 0.7, 0.4); add_child(rock); rock.position = pos; rock.rotation = Vector3(randf(), randf(), randf()) * PI

func scatter_targets(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0: continue
		create_target_at(Vector3(x, y + 1.5, z))

func create_target_at(pos):
	var target = target_scene.instantiate(); add_child(target); target.position = pos; target.look_at(Vector3(0, pos.y, 0), Vector3.UP); target.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

func scatter_enemies(small_count, big_count):
	for i in range(small_count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0: continue
		create_enemy_at(Vector3(x, y + 1.0, z), false)
	for i in range(big_count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0: continue
		create_enemy_at(Vector3(x, y + 2.0, z), true)

func create_enemy_at(pos, is_big):
	var enemy = enemy_scene.instantiate(); if is_big: enemy.set_script(load("res://BigEnemy.gd")); enemy.name = "BigEnemy"
	add_child(enemy); enemy.position = pos

func scatter_collectibles(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0: continue
		var item = (collectible_speed_scene if i % 2 == 0 else collectible_health_scene).instantiate()
		add_child(item); item.position = Vector3(x, y + 1.0, z)
