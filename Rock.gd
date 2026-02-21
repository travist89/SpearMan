# Rock Projectile for "Age of Manwe"
# Similar to the Spear, but can hurt BOTH players and enemies.
extends RigidBody3D

@export var damage = 15
@export var impact_force = 10.0

func _ready():
	# Rigidbody3D setup for collision detection
	contact_monitor = true
	max_contacts_reported = 1
	connect("body_entered", _on_body_entered)
	
	if has_meta("initial_velocity"):
		linear_velocity = get_meta("initial_velocity")
	
	# Rocks automatically despawn (delete) after 10 seconds to save memory
	await get_tree().create_timer(10.0).timeout
	if is_instance_valid(self):
		queue_free()

func _on_body_entered(body):
	# Only server handles game logic
	if not multiplayer.is_server(): return

	if body.has_method("take_damage"):
		# Rocks are dangerous! They damage anyone they hit.
		# If it's a player (integer name), we use the RPC version to sync health.
		if body.name.is_valid_int():
			body.take_damage.rpc(damage)
		else:
			# Otherwise it's an AI, so we can just call it directly.
			body.take_damage(damage)
		
		# If the thing we hit is a physics object (like a character),
		# apply a little push back from the impact.
		if body is CharacterBody3D:
			var direction = -global_transform.basis.z
			body.velocity += direction * impact_force
			
		queue_free() # Rock breaks/disappears on impact
		return
	
	# If we hit an explosive target
	if body.has_method("explode"):
		body.explode.rpc()
		queue_free()
		return
