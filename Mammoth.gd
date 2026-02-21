# Aggressive Megafauna AI for "Age of Manwe"
# Mammoths are powerful creatures that will chase and damage players.
# Like the regular Enemy, this logic only runs on the Server in multiplayer.
extends CharacterBody3D

# Exported variables for tweaking Mammoth behavior in the Editor
@export var speed = 3.0
@export var run_speed = 8.0
@export var detection_radius = 25.0
@export var attack_radius = 5.0
@export var damage = 50.0 # Mammoths deal much more damage than regular enemies!
@export var max_health = 250.0
@export var health = 250.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var player = null
var state = "wander"
var wander_target = Vector3.ZERO
var wander_timer = 0.0

func _ready():
	# --- MULTIPLAYER LOGIC ---
	# Only the server should handle Mammoth AI and movement.
	# This ensures the Mammoth is in the same place for all players.
	if not multiplayer.is_server():
		set_physics_process(false)
		return

# Called by projectiles or rocks
func take_damage(amount):
	if not multiplayer.is_server(): return
	health -= amount
	# The mammoth gets scared and runs away (flee) when hit
	state = "flee"
	if health <= 0:
		# Call the death RPC so everyone sees the mammoth die
		die.rpc()

# Finds the nearest player node in the scene
func find_nearest_player():
	var nearest = null
	var min_dist = INF
	for node in get_parent().get_children():
		# Checks if the node name is a Peer ID (integer)
		if node is CharacterBody3D and node.name.is_valid_int():
			var dist = global_position.distance_to(node.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = node
	return nearest

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Update target information
	player = find_nearest_player()

	if player:
		var dist = global_position.distance_to(player.global_position)
		
		# Change AI state based on how close the player is
		if dist < detection_radius:
			state = "chase"
		elif state == "chase" and dist > detection_radius * 1.5:
			state = "wander"
			
	# --- AI State Machine ---
	if state == "chase" and player:
		# Move quickly towards the player
		var direction = (player.global_position - global_position).normalized()
		direction.y = 0 
		velocity.x = direction.x * run_speed
		velocity.z = direction.z * run_speed
		
		# Look at the player
		var target_pos = Vector3(player.global_position.x, global_position.y, player.global_position.z)
		if global_position.distance_squared_to(target_pos) > 0.1:
			look_at(target_pos, Vector3.UP)
		
	elif state == "wander":
		# Move slowly and occasionally pick a new destination
		wander_timer -= delta
		if wander_timer <= 0:
			wander_timer = randf_range(5.0, 10.0) # Move less often than regular enemies
			var random_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			wander_target = global_position + random_dir * 15.0
		
		var direction = (wander_target - global_position).normalized()
		# Stop if we've reached the wander target
		if global_position.distance_to(wander_target) < 1.0:
			velocity.x = 0
			velocity.z = 0
		else:
			velocity.x = direction.x * speed 
			velocity.z = direction.z * speed
		
		if velocity.length() > 0.1:
			look_at(global_position + velocity, Vector3.UP)

	# Execute the calculated movement
	move_and_slide()
	
	# --- Attack Logic ---
	# Handle damage via direct physical collision. 
	# This ensures the mammoth deals damage if it runs into a player.
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var body = collision.get_collider()
		# Only damage nodes that represent real players (integer names)
		if body.has_method("take_damage") and body.name.is_valid_int():
			# Trigger the damage RPC on the player so the client sees it!
			body.take_damage.rpc(damage * delta)

# RPC to handle Mammoth death across the network
@rpc("any_peer", "call_local", "reliable")
func die():
	print("Mammoth Died!")
	# Currently just disappears, but could spawn items or play an animation
	queue_free()
