# Target script for "Age of Manwe"
# Targets are simple objects that explode when hit by a projectile.
extends StaticBody3D

# This function is called by projectiles (Spear/Rock) when they hit the target
@rpc("any_peer", "call_local", "reliable")
func explode():
	print("Target Hit!")
	# Create a simple visual effect before disappearing
	spawn_particles()
	# remove the target from the scene
	queue_free()

func spawn_particles():
	# CPUParticles3D are easier to use for beginners than GPU particles
	var particles = CPUParticles3D.new()
	# Add particles to the scene root so they don't disappear when the target is deleted
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	
	# Explosion look and feel settings
	particles.emitting = true
	particles.amount = 15
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 6.0
	
	# Automatically clean up the particles after a delay
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()
