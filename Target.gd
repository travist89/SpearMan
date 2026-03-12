# Breakable Target Logic for "Age of Manwe"
extends StaticBody3D

@rpc("any_peer", "call_local", "reliable")
func explode(killer_id = 0):
	spawn_particles()
	
	if killer_id != 0 and multiplayer.is_server():
		var player_node = get_tree().root.find_child(str(killer_id), true, false)
		
		if player_node and player_node.has_method("add_score"):
			player_node.add_score.rpc(100) 
			
	queue_free()

func spawn_particles():
	var particles = CPUParticles3D.new()
	
	# Add particles to the Scene Root so they survive the Target's queue_free()
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	
	particles.emitting = true
	particles.amount = 15
	particles.one_shot = true       
	particles.explosiveness = 1.0   
	particles.lifetime = 1.0
	particles.spread = 180.0
	particles.gravity = Vector3(0, -9.8, 0)
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 6.0
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0)
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.2, 0.2, 0.2)
	mesh.material = mat
	particles.mesh = mesh
	
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(particles):
		particles.queue_free()
