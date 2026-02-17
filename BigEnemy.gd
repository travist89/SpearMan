extends "res://Enemy.gd"

func _ready():
	# Higher stats for Big Enemy
	max_health = 100.0
	health = 100.0
	speed = 2.5 # Slower but tougher
	damage = 40
	scale = Vector3(2, 2, 2) # Larger
	
	super._ready()
	
	if multiplayer.is_server():
		create_legs()

func create_legs():
	for i in range(4):
		var leg = MeshInstance3D.new()
		var leg_mesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.1
		leg_mesh.bottom_radius = 0.1
		leg_mesh.height = 1.5
		leg.mesh = leg_mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.2)
		leg.material_override = mat
		
		add_child(leg)
		
		# Position legs at corners
		var angle = (PI/2) * i + (PI/4)
		leg.position = Vector3(cos(angle) * 0.4, -0.5, sin(angle) * 0.4)
		leg.rotation.z = deg_to_rad(15) if cos(angle) > 0 else deg_to_rad(-15)
		
		# Give legs their own MultiplayerSynchronizer? 
		# No, as children of the Enemy they will move with it.
		# But to be safe, since they are added at runtime, they won't be in the scene for clients.
		# I should make BigEnemy a separate Scene or use an RPC to create legs on clients.
		# Let's use an RPC.
		create_legs_on_clients.rpc()

@rpc("call_local")
func create_legs_on_clients():
	if has_node("Leg0"): return # Already created
	
	for i in range(4):
		var leg = MeshInstance3D.new()
		leg.name = "Leg" + str(i)
		var leg_mesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.1
		leg_mesh.bottom_radius = 0.1
		leg_mesh.height = 1.5
		leg.mesh = leg_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.2)
		leg.material_override = mat
		add_child(leg)
		var angle = (PI/2) * i + (PI/4)
		leg.position = Vector3(cos(angle) * 0.4, -0.5, sin(angle) * 0.4)
