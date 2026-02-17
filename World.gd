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
var terrain_height = 15.0 # Increased height for more variety
var terrain_resolution = 100 
var lake_level = -2.0 # Height at which "mustard" appears

func _ready():
	# Networking Spawner
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
	
	randomize()
	noise.seed = 12345 
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
	add_player(1) 
	print("Hosting...")

func start_join():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		return

	peer.create_client("127.0.0.1", 13579)
	multiplayer.multiplayer_peer = peer
	print("Joining...")
	if has_node("Player"):
		$Player.queue_free()

func add_player(id = 1):
	if not multiplayer.is_server(): return

	var player = player_scene.instantiate()
	player.name = str(id)
	add_child(player)
	player.position = Vector3(0, 15, 0) # Spawn higher
	
	if has_node("Player"):
		$Player.queue_free()

func setup_environment():
	create_terrain() 
	create_mustard_lakes()
	
	if multiplayer.is_server():
		scatter_targets(30)
		scatter_enemies(15)
		scatter_collectibles(20)
		scatter_pretzel_trees(60)

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
			
			# Flatten spawn area
			if abs(world_x) < 10 and abs(world_z) < 10:
				y = lerp(y, 2.0, 0.8) # Keep it slightly above water
			
			var color = Color(0.4, 0.25, 0.1) # Bread/Crust brown
			if y < lake_level + 0.5:
				color = Color(0.8, 0.7, 0.2) # Saturated yellow for "sandy mustard" edges
			elif y > 5.0:
				color = Color(0.5, 0.3, 0.15) # Darker crust
				
			st.set_color(color)
			st.set_uv(Vector2(percent_x, percent_z))
			st.add_vertex(Vector3(world_x, y, world_z))

	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var vert = z * (terrain_resolution + 1) + x
			st.add_index(vert)
			st.add_index(vert + 1)
			st.add_index(vert + terrain_resolution + 1)
			st.add_index(vert + 1)
			st.add_index(vert + terrain_resolution + 2)
			st.add_index(vert + terrain_resolution + 1)

	st.generate_normals()
	var mesh = st.commit()
	
	var terrain = StaticBody3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh_inst.material_override = mat
	terrain.add_child(mesh_inst)
	
	var col = CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	terrain.add_child(col)

func create_mustard_lakes():
	var lake_mesh = PlaneMesh.new()
	lake_mesh.size = Vector2(terrain_size, terrain_size)
	
	var lake_inst = MeshInstance3D.new()
	lake_inst.mesh = lake_mesh
	lake_inst.position.y = lake_level
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.8, 0.0) # Bright Mustard Yellow
	mat.roughness = 0.1 # Shiny
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.15, 0) # Subtle glow
	lake_inst.material_override = mat
	
	add_child(lake_inst)

func scatter_pretzel_trees(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		var z = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		
		var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level + 1.0 or (abs(x) < 12 and abs(z) < 12):
			continue # Don't spawn in mustard or at start
			
		create_pretzel_tree_at(Vector3(x, y, z))

func create_pretzel_tree_at(pos):
	var tree = Node3D.new()
	tree.name = "PretzelTree"
	add_child(tree)
	tree.position = pos
	
	# Trunk (Pretzel Stick)
	var trunk = MeshInstance3D.new()
	var trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.2
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 3.0
	trunk.mesh = trunk_mesh
	
	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.2, 0.1) # Dark brown pretzel
	trunk.material_override = trunk_mat
	trunk.position.y = 1.5
	tree.add_child(trunk)
	
	# Pretzel "Leaves" (Torus shape or twisted loops)
	for i in range(3):
		var loop = MeshInstance3D.new()
		var loop_mesh = TorusMesh.new()
		loop_mesh.inner_radius = 0.4
		loop_mesh.outer_radius = 0.8
		loop.mesh = loop_mesh
		loop.material_override = trunk_mat
		loop.position.y = 2.5 + (i * 0.5)
		loop.rotation.x = randf_range(0, PI)
		loop.rotation.y = randf_range(0, PI)
		tree.add_child(loop)
		
		# Salt Grains
		for j in range(5):
			var salt = MeshInstance3D.new()
			var salt_mesh = BoxMesh.new()
			salt_mesh.size = Vector3(0.1, 0.1, 0.1)
			salt.mesh = salt_mesh
			var salt_mat = StandardMaterial3D.new()
			salt_mat.albedo_color = Color(1, 1, 1) # White salt
			salt.material_override = salt_mat
			
			var angle = randf_range(0, TAU)
			var radius = 0.7
			salt.position = Vector3(cos(angle)*radius, 0, sin(angle)*radius)
			loop.add_child(salt)

func scatter_targets(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		var z = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level: continue
		create_target_at(Vector3(x, y + 1.5, z))

func create_target_at(pos):
	var target = target_scene.instantiate()
	add_child(target)
	target.position = pos
	target.look_at(Vector3(0, pos.y, 0), Vector3.UP)
	target.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

func scatter_enemies(count):
	for i in range(count):
		var x = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		var z = randf_range(-terrain_size/2 * 0.9, terrain_size/2 * 0.9)
		var y = noise.get_noise_2d(x, z) * terrain_height
		if y < lake_level: continue
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
		if y < lake_level: continue
		var type = "health" if i % 2 == 0 else "speed"
		create_collectible_at(Vector3(x, y + 1.0, z), type)

func create_collectible_at(pos, type):
	var item = collectible_speed_scene.instantiate() if type == "speed" else collectible_health_scene.instantiate()
	add_child(item)
	item.position = pos
