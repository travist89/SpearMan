# Breakable Target Logic for "Age of Manwe"
#
# This script handles static targets that players can shoot for points.
# It demonstrates a simple "Destructible Object" pattern.
#
# Network Architecture:
# - Targets are spawned by the Server via MultiplayerSpawner.
# - Destruction is triggered via RPC `explode()` from the projectile.
# - Scoring is handled on the Server and synced to the player via RPC.

extends StaticBody3D

# --------------------------------------------------------------------------------------------------
# DESTRUCTION & SCORING
# --------------------------------------------------------------------------------------------------

# RPC: Triggers the explosion sequence on all clients.
# @param killer_id: The Peer ID of the player who destroyed this target.
@rpc("any_peer", "call_local", "reliable")
func explode(killer_id = 0):
	print("Target Hit by Player ID: ", killer_id)
	
	# --- Visual Effects ---
	# We spawn particles BEFORE deleting the object.
	spawn_particles()
	
	# --- Scoring Logic (Server Only) ---
	# Only the Server updates the score to prevent cheating.
	if killer_id != 0 and multiplayer.is_server():
		# Find the player node with the matching peer ID (Name is ID)
		# We search the SceneTree root for a node named "12345" etc.
		var player_node = get_tree().root.find_child(str(killer_id), true, false)
		
		# If found, award points via RPC
		if player_node and player_node.has_method("add_score"):
			player_node.add_score.rpc(100) # Award 100 points
			
	# --- Cleanup ---
	# Remove the target from the scene.
	# The MultiplayerSpawner will automatically delete it on all clients.
	queue_free()

# --------------------------------------------------------------------------------------------------
# VISUAL EFFECTS
# --------------------------------------------------------------------------------------------------

func spawn_particles():
	# Create a temporary particle emitter
	var particles = CPUParticles3D.new()
	
	# IMPORTANT: Add particles to the Scene Root, NOT as a child of this Target.
	# If we added it as a child, the particles would disappear instantly when queue_free() is called below.
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	
	# Configure Explosion Effect
	particles.emitting = true
	particles.amount = 15
	particles.one_shot = true       # Emit once, then stop
	particles.explosiveness = 1.0   # All particles burst at once
	particles.lifetime = 1.0
	particles.spread = 180.0
	particles.gravity = Vector3(0, -9.8, 0)
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 6.0
	
	# Create a simple debris mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0) # Red debris
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.2, 0.2, 0.2)
	mesh.material = mat
	particles.mesh = mesh
	
	# Lifecycle Management
	# Wait for particles to finish, then delete the emitter node.
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(particles):
		particles.queue_free()
