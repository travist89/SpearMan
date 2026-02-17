extends StaticBody3D

@rpc("any_peer", "call_local", "reliable")
func explode():
	print("Target Exploded!")
	spawn_particles()
	
	# Force deletion on all clients to ensure it disappears
	queue_free()

func spawn_particles():
	# Create explosion particles
	var particles = CPUParticles3D.new()
	# Add to root so it persists after Target queue_free
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	
	# Configure particles
	particles.emitting = true
	particles.amount = 20
	particles.lifetime = 1.0
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.spread = 180.0
	particles.gravity = Vector3(0, -10, 0)
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 10.0
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.0
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.5, 0) # Orange
	mat.emission_enabled = true
	mat.emission = Color(1, 0.5, 0)
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.2, 0.2, 0.2)
	mesh.material = mat
	particles.mesh = mesh
	
	# Clean up particles after they finish
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()
