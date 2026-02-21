# Spear Projectile for "Age of Manwe"
# This script handles the flight and collision of a thrown spear.
extends RigidBody3D

@export var damage = 10
@export var stick_probability = 0.8

func _ready():
	# Rigidbody3D setup for collision detection
	contact_monitor = true
	max_contacts_reported = 1
	# Connect the "body_entered" signal to our custom function
	connect("body_entered", _on_body_entered)
	
	# If we want the spear to start with a specific speed, 
	# we can pass it through "metadata" when spawning.
	if has_meta("initial_velocity"):
		linear_velocity = get_meta("initial_velocity")

# This function is called when the spear hits something
func _on_body_entered(body):
	# --- MULTIPLAYER SECURITY ---
	# Only the server should handle game logic like dealing damage.
	# This prevents cheating and ensuring everyone sees the same outcome.
	if not multiplayer.is_server(): return

	# Check if we hit something that can take damage
	if body.has_method("take_damage"):
		# In this game, spears only hurt AI enemies (non-player nodes).
		# Player nodes have integer names (Peer IDs).
		if not body.name.is_valid_int():
			body.take_damage(damage)
			# Destroy the spear after hitting an enemy
			queue_free()
			return

	# If we hit an explosive target or enemy
	if body.has_method("explode"):
		# Trigger the explosion RPC for everyone
		body.explode.rpc()
		queue_free()
		return

	# "Sticky" physics logic:
	# If we hit the ground or a wall, stop moving and stay stuck there!
	if body is StaticBody3D or body is CSGShape3D:
		# freeze stops the physics simulation for this object
		freeze = true
		set_deferred("freeze", true)
		# Disable collision shape so players don't trip on stuck spears
		$CollisionShape3D.set_deferred("disabled", true)
