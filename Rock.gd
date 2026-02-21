extends RigidBody3D

@export var damage = 15
@export var impact_force = 10.0

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	connect("body_entered", _on_body_entered)
	
	# Check for initial velocity passed from spawner
	if has_meta("initial_velocity"):
		linear_velocity = get_meta("initial_velocity")
	
	# Rocks automatically despawn after 10 seconds
	await get_tree().create_timer(10.0).timeout
	if is_instance_valid(self):
		queue_free()

func _on_body_entered(body):
	if not multiplayer.is_server(): return

	if body.has_method("take_damage"):
		# Rocks deal damage to both enemies and players!
		body.take_damage(damage)
		
		# Apply physics impulse if possible
		if body is CharacterBody3D:
			var direction = -global_transform.basis.z
			body.velocity += direction * impact_force
			
		queue_free()
		return
	
	if body.has_method("explode"):
		body.explode.rpc()
		queue_free()
		return
