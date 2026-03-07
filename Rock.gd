# Rock Projectile Logic for "Age of Manwe"
#
# This script controls the Rock weapon, which is distinct from the Spear.
# Key Differences:
# - Can damage BOTH players and enemies (Friendly Fire enabled).
# - Applies knockback force on impact.
# - Despawns after 10 seconds or upon hitting a valid target.
# - Does NOT stick to walls/enemies.

extends RigidBody3D

# --- Configuration ---
@export var damage: float = 15.0         # Damage dealt on impact
@export var impact_force: float = 10.0   # Knockback strength

# --------------------------------------------------------------------------------------------------
# INITIALIZATION
# --------------------------------------------------------------------------------------------------

func _ready():
	# --- Physics Setup ---
	contact_monitor = true
	max_contacts_reported = 1
	connect("body_entered", _on_body_entered)
	
	# Apply initial velocity if provided by spawner
	if has_meta("initial_velocity"):
		linear_velocity = get_meta("initial_velocity")
	
	# --- Lifecycle Management ---
	# Automatically destroy the rock after 10 seconds to prevent lag from too many objects.
	# We use a timer here that runs on all clients, ensuring cleanup happens everywhere.
	# Note: Technically the Server should decide despawn, but for simple projectiles 
	# a local timer is usually acceptable if the despawn doesn't trigger game logic.
	# However, since this is a networked object spawned by MultiplayerSpawner, 
	# only the Server's queue_free() matters. Clients will just see it vanish when the Server kills it.
	if multiplayer.is_server():
		await get_tree().create_timer(10.0).timeout
		if is_instance_valid(self):
			queue_free()

# --------------------------------------------------------------------------------------------------
# COLLISION LOGIC (Server Only)
# --------------------------------------------------------------------------------------------------

func _on_body_entered(body):
	# Security: Only Server processes collisions
	if not multiplayer.is_server(): return

	# --- Damage Dealing ---
	if body.has_method("take_damage"):
		# Check if target is a Player (Peer ID name)
		if body.name.is_valid_int():
			# Call RPC to damage player on their client
			body.take_damage.rpc(damage)
		else:
			# Call direct method for AI enemies
			body.take_damage(damage)
		
		# --- Knockback ---
		# If we hit a CharacterBody3D (Player/Enemy), push them back.
		if body is CharacterBody3D:
			# Direction is the rock's forward vector
			var direction = -global_transform.basis.z.normalized()
			# Apply velocity impulse (Note: CharacterBody3D velocity is usually reset in physics_process,
			# so this effect might be fleeting unless handled in the character script)
			body.velocity += direction * impact_force
			
		# Destroy Rock on impact
		queue_free() 
		return
	
	# --- Explosive Interaction ---
	if body.has_method("explode"):
		body.explode.rpc()
		queue_free()
		return
