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
var terrain_height = 15.0 
var terrain_resolution = 100 
var lake_level = -2.0 

# Day/Night Cycle
var time = 0.0
var day_duration = 60.0 # Seconds for a full day
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment

func _ready():
	var spawner = MultiplayerSpawner.new()
	spawner.spawn_path = get_path()
	spawner.add_spawnable_scene(player_scene.resource_path)
	spawner.add_spawnable_scene(spear_scene.resource_path)
	spawner.add_spawnable_scene(enemy_scene.resource_path)
	spawner.add_spawnable_scene(target_scene.resource_path)
	spawner.add_spawnable_scene(collectible_health_scene.resource_path)
	spawner.add_spawnable_scene(collectible_speed_scene.resource_path)
	add_child(spawner)
	
	create_multiplayer_ui()
	setup_lighting_and_sky()
	
	randomize()
	noise.seed = 12345 
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	
	setup_environment()

func _process(delta):
	update_day_night_cycle(delta)

func setup_lighting_and_sky():
	# World Environment
	world_env = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	
	# Starry night setup
	sky_mat.sky_top_color = Color(0.1, 0.1, 0.3)
	sky_mat.sky_horizon_color = Color(0.5, 0.4, 0.5)
	sky_mat.ground_bottom_color = Color(0.1, 0.1, 0.1)
	sky_mat.ground_horizon_color = Color(0.5, 0.4, 0.5)
	
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	
	# Glow for mustard and stars
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.2
	
	world_env.environment = env
	add_child(world_env)
	
	# Sun
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.9, 0.8)
	add_child(sun)
	
	# Moon
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = true
	moon.light_color = Color(0.4, 0.5, 0.8)
	moon.light_intensity = 0.5
	add_child(moon)

func update_day_night_cycle(delta):
	time += delta
	var progress = fmod(time / day_duration, 1.0)
	var angle = progress * TAU
	
	# Rotate Sun & Moon
	sun.rotation.x = angle
	moon.rotation.x = angle + PI
	
	# Adjust energy based on altitude
	sun.light_energy = clamp(sin(angle) * 2.0, 0.0, 1.2)
	moon.light_energy = clamp(sin(angle + PI) * 2.0, 0.0, 0.8)
	
	# Adjust sky colors for sunrise/sunset
	var sky_mat = world_env.environment.sky.sky_material
	var day_color = Color(0.4, 0.6, 1.0)
	var night_color = Color(0.02, 0.02, 0.1)
	var lerp_val = clamp(sin(angle) + 0.5, 0.0, 1.0)
	sky_mat.sky_top_color = night_color.lerp(day_color, lerp_val)

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
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED: return
	peer.create_server(13579)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(add_player)
	add_player(1) 
	print("Hosting...")

func start_join():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED: return
	peer.create_client("127.0.0.1", 13579)
	multiplayer.multiplayer_peer = peer
	if has_node("Player"): $Player.queue_free()

func add_player(id = 1):
	if not multiplayer.is_server(): return
	var player = player_scene.instantiate()
	player.name = str(id)
	add_child(player)
	player.position = Vector3(0, 15, 0) 
	if has_node("Player"): $Player.queue_free()

func setup_environment():
	create_terrain() 
	create_mustard_lakes()
	if multiplayer.is_server():
		scatter_targets(30)
		scatter_enemies(12, 5)
		scatter_collectibles(20)
		scatter_pretzel_trees(60)
		scatter_crouton_rocks(40)

func create_terrain():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(terrain_resolution + 1):
		for x in range(terrain_resolution + 1):
			var percent_x = float(x) / terrain_resolution
			var percent_z = float(z) / terrain_resolution
			var world_x = (percent_x - 0.5) * terrain_size
			var world_z = (percent_z - 0.5) * terrain_size
			var y = noise.get_noise_2d(world_x, world_z) * terrain_height
			if abs(world_x) < 10 and abs(world_z) < 10: y = lerp(y, 2.0, 0.8)
			var color = Color(0.4, 0.25, 0.1) 
			if y < lake_level + 0.5: color = Color(0.8, 0.7, 0.2) 
			elif y > 5.0: color = Color(0.5, 0.3, 0.15) 
			st.set_color(color)
			st.add_vertex(Vector3(world_x, y, world_z))
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var vert = z * (terrain_resolution + 1) + x
			st.add_index(vert); st.add_index(vert + 1); st.add_index(vert + terrain_resolution + 1)
			st.add_index(vert + 1); st.add_index(vert + terrain_resolution + 2); st.add_index(vert + terrain_resolution + 1)
	st.generate_normals()
	var terrain = StaticBody3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh_inst.material_override = mat
	terrain.add_child(mesh_inst)
	var col = CollisionShape3D.new()
	col.shape = mesh_inst.mesh.create_trimesh_shape()
	terrain.add_child(col)

func create_mustard_lakes():
	var lake_inst = MeshInstance3D.new()
	lake_inst.mesh = PlaneMesh.new(); lake_inst.mesh.size = Vector2(terrain_size, terrain_size)
	lake_inst.position.y = lake_level
	var mat = StandardMaterial3D.new(); mat.albedo_color = Color(0.9, 0.8, 0.0); mat.roughness = 0.1; mat.emission_enabled = true; mat.emission = Color(0.2, 0.15, 0) 
	lake_inst.material_override = mat
	add_child(lake_inst)

func scatter_pretzel_trees(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2)
		var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0 or (abs(x) < 12 and abs(z) < 12): continue
		create_pretzel_tree_at(Vector3(x, y, z))

func create_pretzel_tree_at(pos):
	var tree = Node3D.new(); tree.name = "PretzelTree"; add_child(tree); tree.position = pos
	var trunk = MeshInstance3D.new(); trunk.mesh = CylinderMesh.new(); trunk.mesh.top_radius = 0.2; trunk.mesh.bottom_radius = 0.3; trunk.mesh.height = 3.0
	var trunk_mat = StandardMaterial3D.new(); trunk_mat.albedo_color = Color(0.4, 0.2, 0.1); trunk.material_override = trunk_mat; trunk.position.y = 1.5; tree.add_child(trunk)
	for i in range(3):
		var loop = MeshInstance3D.new(); loop.mesh = TorusMesh.new(); loop.mesh.inner_radius = 0.4; loop.mesh.outer_radius = 0.8; loop.material_override = trunk_mat; loop.position.y = 2.5 + (i * 0.5); loop.rotation = Vector3(randf(), randf(), randf()) * PI; tree.add_child(loop)
		for j in range(5):
			var salt = MeshInstance3D.new(); salt.mesh = BoxMesh.new(); salt.mesh.size = Vector3(0.1, 0.1, 0.1); salt.material_override = StandardMaterial3D.new(); salt.material_override.albedo_color = Color(1,1,1); var a = randf()*TAU; salt.position = Vector3(cos(a)*0.7, 0, sin(a)*0.7); loop.add_child(salt)

func scatter_crouton_rocks(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2)
		var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 0.5: continue
		create_crouton_rock_at(Vector3(x, y, z))

func create_crouton_rock_at(pos):
	var rock = MeshInstance3D.new()
	rock.mesh = BoxMesh.new(); rock.mesh.size = Vector3(randf_range(1, 3), randf_range(1, 2), randf_range(1, 3))
	var mat = StandardMaterial3D.new(); mat.albedo_color = Color(0.8, 0.6, 0.3) # Toasty Crouton
	rock.material_override = mat
	add_child(rock); rock.position = pos; rock.rotation = Vector3(randf(), randf(), randf()) * PI

func scatter_targets(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level: continue
		create_target_at(Vector3(x, y + 1.5, z))

func create_target_at(pos):
	var target = target_scene.instantiate(); add_child(target); target.position = pos; target.look_at(Vector3(0, pos.y, 0), Vector3.UP); target.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

func scatter_enemies(small_count, big_count):
	for i in range(small_count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level: continue
		create_enemy_at(Vector3(x, y + 1.0, z), false)
	for i in range(big_count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level: continue
		create_enemy_at(Vector3(x, y + 2.0, z), true)

func create_enemy_at(pos, is_big):
	var enemy = enemy_scene.instantiate(); if is_big: enemy.set_script(load("res://BigEnemy.gd")); enemy.name = "BigEnemy"
	add_child(enemy); enemy.position = pos

func scatter_collectibles(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2, terrain_size/2); var z = randf_range(-terrain_size/2, terrain_size/2); var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level: continue
		var item = (collectible_speed_scene if i % 2 == 0 else collectible_health_scene).instantiate()
		add_child(item); item.position = Vector3(x, y + 1.0, z)
