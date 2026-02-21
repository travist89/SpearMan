extends RigidBody3D

@export var damage = 10
@export var stick_probability = 0.8

func _ready():
	# Connect the body_entered signal for collision handling
	contact_monitor = true
	max_contacts_reported = 1
	connect("body_entered", _on_body_entered)
	
	# Check for initial velocity passed from spawner
	if has_meta("initial_velocity"):
		linear_velocity = get_meta("initial_velocity")

func _on_body_entered(body):
	# Only server handles collisions and game logic
	if not multiplayer.is_server(): return

	# Check if we hit an enemy or target
	if body.has_method("take_damage") and not body.name.is_valid_int():
		body.take_damage(damage)
		queue_free()
		return

	if body.has_method("explode"):
		# Trigger RPC so all clients see explosion and delete the object
		body.explode.rpc()
		# Destroy the spear
		queue_free()
		return

	# Simple logic to stick the spear into objects
	if body is StaticBody3D or body is CSGShape3D:
		freeze = true
		set_deferred("freeze", true)
		$CollisionShape3D.set_deferred("disabled", true)
