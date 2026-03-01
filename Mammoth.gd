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
var anim_player: AnimationPlayer

var player = null
var state = "wander"
var wander_target = Vector3.ZERO
var wander_timer = 0.0
var run_timeout = 0.0 # Timer to smooth out animation transitions

func _ready():
	# --- MULTIPLAYER LOGIC ---
	# Only the server should handle Mammoth AI and movement.
	# This ensures the Mammoth is in the same place for all players.
	setup_animations()
	
	if not multiplayer.is_server():
		set_physics_process(false)
		return

func setup_animations():
	anim_player = AnimationPlayer.new()
	add_child(anim_player)
	
	var library = AnimationLibrary.new()
	
	# --- Idle Animation ---
	var idle_anim = Animation.new()
	idle_anim.loop_mode = Animation.LOOP_LINEAR
	idle_anim.length = 4.0
	var track_idx = idle_anim.add_track(Animation.TYPE_VALUE)
	idle_anim.track_set_path(track_idx, "Head:rotation")
	# Original rotation is roughly (0, PI, 0) because of the -1 scale in transform matrix
	# But checking the Transform3D(-1, ...) implies 180 degrees rotation.
	var base_rot = Vector3(0, PI, 0)
	idle_anim.track_insert_key(track_idx, 0.0, base_rot + Vector3(0, 0, 0))
	idle_anim.track_insert_key(track_idx, 2.0, base_rot + Vector3(deg_to_rad(5), deg_to_rad(10), 0)) # Sway head
	idle_anim.track_insert_key(track_idx, 4.0, base_rot + Vector3(0, 0, 0))
	
	# Legs (Idle) - keep them still
	for leg_name in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		track_idx = idle_anim.add_track(Animation.TYPE_VALUE)
		idle_anim.track_set_path(track_idx, leg_name + ":rotation")
		idle_anim.track_insert_key(track_idx, 0.0, Vector3.ZERO)
		idle_anim.track_insert_key(track_idx, 4.0, Vector3.ZERO)
	
	# Tail (Idle) - sway wildly
	track_idx = idle_anim.add_track(Animation.TYPE_VALUE)
	idle_anim.track_set_path(track_idx, "Tail:rotation")
	var tail_base_rot = Vector3(deg_to_rad(-135), 0, 0)
	# Add a figure-8 wobble
	idle_anim.track_insert_key(track_idx, 0.0, tail_base_rot)
	idle_anim.track_insert_key(track_idx, 1.0, tail_base_rot + Vector3(deg_to_rad(10), 0, deg_to_rad(30))) # Up-Left
	idle_anim.track_insert_key(track_idx, 2.0, tail_base_rot + Vector3(0, 0, 0)) # Center
	idle_anim.track_insert_key(track_idx, 3.0, tail_base_rot + Vector3(deg_to_rad(-10), 0, deg_to_rad(-30))) # Down-Right
	idle_anim.track_insert_key(track_idx, 4.0, tail_base_rot)
	
	library.add_animation("Idle", idle_anim)
	
	# --- Run Animation ---
	var run_anim = Animation.new()
	run_anim.loop_mode = Animation.LOOP_LINEAR
	run_anim.length = 0.8
	
	# Body Bob
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	run_anim.track_set_path(track_idx, "Body:position")
	# Base Y is 2.5, Z is 1.0
	run_anim.track_insert_key(track_idx, 0.0, Vector3(0, 2.5, 1.0))
	run_anim.track_insert_key(track_idx, 0.4, Vector3(0, 2.7, 1.0))
	run_anim.track_insert_key(track_idx, 0.8, Vector3(0, 2.5, 1.0))
	
	# Head Bob
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	run_anim.track_set_path(track_idx, "Head:position")
	# Base Y is 4.0, Z is roughly -0.5
	run_anim.track_insert_key(track_idx, 0.0, Vector3(0, 4.0, -0.5))
	run_anim.track_insert_key(track_idx, 0.4, Vector3(0, 3.8, -0.5)) # Counter-bob
	run_anim.track_insert_key(track_idx, 0.8, Vector3(0, 4.0, -0.5))
	
	# Head Rotation during Run (Keep it facing correctly)
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	run_anim.track_set_path(track_idx, "Head:rotation")
	run_anim.track_insert_key(track_idx, 0.0, base_rot)
	run_anim.track_insert_key(track_idx, 0.8, base_rot)
	
	# Tail (Run) - bob and sway frantically
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	run_anim.track_set_path(track_idx, "Tail:rotation")
	# Flap up/down 45 degrees, sway left/right 30 degrees
	run_anim.track_insert_key(track_idx, 0.0, tail_base_rot + Vector3(deg_to_rad(-20), 0, deg_to_rad(30))) # Down-Left
	run_anim.track_insert_key(track_idx, 0.2, tail_base_rot + Vector3(deg_to_rad(25), 0, 0)) # Up-Center
	run_anim.track_insert_key(track_idx, 0.4, tail_base_rot + Vector3(deg_to_rad(-20), 0, deg_to_rad(-30))) # Down-Right
	run_anim.track_insert_key(track_idx, 0.6, tail_base_rot + Vector3(deg_to_rad(25), 0, 0)) # Up-Center
	run_anim.track_insert_key(track_idx, 0.8, tail_base_rot + Vector3(deg_to_rad(-20), 0, deg_to_rad(30))) # Back to Down-Left

	# Legs (Run) - animate walking cycle
	# FL and BR move together, FR and BL move together
	var leg_swing_angle = deg_to_rad(30)
	
	# Front Left & Back Right
	for leg_name in ["LegFL", "LegBR"]:
		track_idx = run_anim.add_track(Animation.TYPE_VALUE)
		run_anim.track_set_path(track_idx, leg_name + ":rotation")
		run_anim.track_insert_key(track_idx, 0.0, Vector3(leg_swing_angle, 0, 0))
		run_anim.track_insert_key(track_idx, 0.4, Vector3(-leg_swing_angle, 0, 0))
		run_anim.track_insert_key(track_idx, 0.8, Vector3(leg_swing_angle, 0, 0))
		
	# Front Right & Back Left
	for leg_name in ["LegFR", "LegBL"]:
		track_idx = run_anim.add_track(Animation.TYPE_VALUE)
		run_anim.track_set_path(track_idx, leg_name + ":rotation")
		run_anim.track_insert_key(track_idx, 0.0, Vector3(-leg_swing_angle, 0, 0))
		run_anim.track_insert_key(track_idx, 0.4, Vector3(leg_swing_angle, 0, 0))
		run_anim.track_insert_key(track_idx, 0.8, Vector3(-leg_swing_angle, 0, 0))
	
	library.add_animation("Run", run_anim)
	
	anim_player.add_animation_library("", library)
	anim_player.play("Idle")

func _process(delta):
	# On clients, we need to check if the mammoth is moving to play animations
	# since physics_process is disabled.
	# We can check if position has changed.
	if not multiplayer.is_server():
		var current_pos = global_position
		if not has_meta("last_pos"): set_meta("last_pos", current_pos)
		var last_pos = get_meta("last_pos")
		var move_speed = current_pos.distance_to(last_pos) / delta
		set_meta("last_pos", current_pos)
		
		# If moving, reset the timeout and play run animation
		if move_speed > 0.1:
			run_timeout = 0.2 # Keep running for 0.2s after stopping
			if anim_player.current_animation != "Run":
				anim_player.play("Run", 0.2)
		else:
			# If stopped, only switch to idle after timeout expires
			# This prevents flickering when network updates are sparse
			run_timeout -= delta
			if run_timeout <= 0:
				if anim_player.current_animation != "Idle":
					anim_player.play("Idle", 0.2)

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
			# Ignore dead players
			if "is_dead" in node and node.is_dead:
				continue

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
	
	if velocity.length() > 0.1:
		anim_player.play("Run")
	else:
		anim_player.play("Idle")
	
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
	if not is_inside_tree(): return
	print("Mammoth Died!")
	# Currently just disappears, but could spawn items or play an animation
	
	# Only the server should remove the object. 
	# The MultiplayerSpawner will automatically handle despawning on clients.
	if multiplayer.is_server():
		queue_free()
