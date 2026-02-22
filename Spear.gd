# Spear Projectile for "Age of Manwe"
# This script handles the flight and collision of a thrown spear.
extends RigidBody3D

@export var damage = 10
@export var stick_probability = 0.8
@export var is_fire_spear = false

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
			# Stick to the enemy instead of destroying
			stick_to_target.rpc(body.get_path())
			return

	# If this is a Fire Spear and the object is flammable (like GrassPatch)
	if is_fire_spear and body.has_method("ignite"):
		body.ignite.rpc()

	# If we hit an explosive target or enemy
	if body.has_method("explode"):
		# Trigger the explosion RPC for everyone
		# Pass the owner_id if available, so the target knows who killed it
		if has_meta("owner_id"):
			var owner_id = get_meta("owner_id")
			# Check if the explode method accepts an argument (Target.gd will)
			# Enemy.gd might not, so we need to be careful.
			# Actually, we can just update both Target.gd and Enemy.gd to accept an optional argument.
			# Or we can check if it's a Target.
			if body.name.begins_with("Target"):
				body.explode.rpc(owner_id)
			else:
				body.explode.rpc()
		else:
			body.explode.rpc()
		queue_free()
		return

	# "Sticky" physics logic:
	# If we hit the ground or a wall, stop moving and stay stuck there!
	if body is StaticBody3D or body is CSGShape3D:
		stick_to_target.rpc(body.get_path())

@rpc("authority", "call_local", "reliable")
func stick_to_target(target_path):
	var target = get_node_or_null(target_path)
	if target:
		# We must defer physics/scene tree changes because this might be called during a physics step
		_perform_stick.call_deferred(target)

func _perform_stick(target):
	if not is_inside_tree(): return
	
	freeze = true
	$CollisionShape3D.disabled = true
	
	# If we hit the world geometry (StaticBody3D), we don't need to do anything else.
	if target is StaticBody3D or target is CSGShape3D:
		return

	# If we hit a moving target (like an Enemy), we need to stick to it.
	# However, we CANNOT use reparent(), because the Spear is spawned by MultiplayerSpawner.
	# Reparenting it out of the World node will cause it to be despawned on clients.
	# Instead, we use a RemoteTransform3D on the target to push its movement to the Spear.
	
	# Create a pivot node on the target at the location where the spear hit
	var pivot = Node3D.new()
	target.add_child(pivot)
	pivot.global_transform = global_transform
	
	# Add a RemoteTransform3D to the pivot
	var remote = RemoteTransform3D.new()
	pivot.add_child(remote)
	remote.remote_path = get_path()
	remote.update_position = true
	remote.update_rotation = true
	remote.update_scale = false
