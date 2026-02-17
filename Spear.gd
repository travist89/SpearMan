extends RigidBody3D

@export var damage = 10
@export var stick_probability = 0.8

func _ready():
	# Connect the body_entered signal for collision handling
	contact_monitor = true
	max_contacts_reported = 1
	connect("body_entered", _on_body_entered)

func _on_body_entered(body):
	# Only server handles collisions and game logic
	if not multiplayer.is_server(): return

	# Check if we hit a target
	if body.has_method("explode"):
		# Trigger RPC so all clients see explosion and delete the object
		body.explode.rpc()
		# Destroy the spear
		queue_free()
		return

	# Simple logic to stick the spear into objects
	if body is StaticBody3D or body is CSGShape3D:
		freeze = true
		# Optionally reparent to stick to moving objects
		# but for now we just freeze physics
		set_deferred("freeze", true)
		# Disable collision to prevent further interaction
		$CollisionShape3D.set_deferred("disabled", true)
