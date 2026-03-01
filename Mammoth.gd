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

var is_dead = false
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var anim_player: AnimationPlayer

var player = null
var state = "wander"
var wander_target = Vector3.ZERO
var wander_timer = 0.0
var run_timeout = 0.0 # Timer to smooth out animation transitions
var visual_root: Node3D

func _ready():
	# Ensure the mammoth only collides with Layer 1
	# and ignores Layer 2 (Grass), so they don't get stuck on grass patches.
	collision_mask = 1 
	
	# FIX: Create a VisualRoot to separate visual rotation (death) from physics rotation (movement).
	# This prevents the Host-side physics logic (specifically look_at()) from resetting the
	# death rotation (lying on side) back to upright. By rotating VisualRoot for death,
	# the root node can spin/reset freely without standing the model back up.
	visual_root = Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)
	
	# Move visual parts to VisualRoot so they rotate with it
	for part_name in ["Body", "Head", "Tail", "LegBL", "LegBR", "LegFL", "LegFR"]:
		var node = get_node_or_null(part_name)
		if node:
			node.reparent(visual_root)
	
	# --- MULTIPLAYER LOGIC ---
	# Only the server should handle Mammoth AI and movement.
	# This ensures the Mammoth is in the same place for all players.
	setup_animations()
	
	if not multiplayer.is_server():
		set_physics_process(false)

func setup_animations():
	anim_player = AnimationPlayer.new()
	add_child(anim_player)
	
	var library = AnimationLibrary.new()
	
	# --- Idle Animation ---
	var idle_anim = Animation.new()
	idle_anim.loop_mode = Animation.LOOP_LINEAR
	idle_anim.length = 4.0
	var track_idx = idle_anim.add_track(Animation.TYPE_VALUE)
	idle_anim.track_set_path(track_idx, "VisualRoot/Head:rotation")
	# Original rotation is roughly (0, PI, 0) because of the -1 scale in transform matrix
	# But checking the Transform3D(-1, ...) implies 180 degrees rotation.
	var base_rot = Vector3(0, PI, 0)
	idle_anim.track_insert_key(track_idx, 0.0, base_rot + Vector3(0, 0, 0))
	idle_anim.track_insert_key(track_idx, 2.0, base_rot + Vector3(deg_to_rad(5), deg_to_rad(10), 0)) # Sway head
	idle_anim.track_insert_key(track_idx, 4.0, base_rot + Vector3(0, 0, 0))
	
	# Legs (Idle) - keep them still
	for leg_name in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		track_idx = idle_anim.add_track(Animation.TYPE_VALUE)
		idle_anim.track_set_path(track_idx, "VisualRoot/" + leg_name + ":rotation")
		idle_anim.track_insert_key(track_idx, 0.0, Vector3.ZERO)
		idle_anim.track_insert_key(track_idx, 4.0, Vector3.ZERO)
	
	# Tail (Idle) - sway wildly
	track_idx = idle_anim.add_track(Animation.TYPE_VALUE)
	idle_anim.track_set_path(track_idx, "VisualRoot/Tail:rotation")
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
	run_anim.track_set_path(track_idx, "VisualRoot/Body:position")
	# Base Y is 2.5, Z is 1.0
	run_anim.track_insert_key(track_idx, 0.0, Vector3(0, 2.5, 1.0))
	run_anim.track_insert_key(track_idx, 0.4, Vector3(0, 2.7, 1.0))
	run_anim.track_insert_key(track_idx, 0.8, Vector3(0, 2.5, 1.0))
	
	# Head Bob
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	run_anim.track_set_path(track_idx, "VisualRoot/Head:position")
	# Base Y is 4.0, Z is roughly -0.5
	run_anim.track_insert_key(track_idx, 0.0, Vector3(0, 4.0, -0.5))
	run_anim.track_insert_key(track_idx, 0.4, Vector3(0, 3.8, -0.5)) # Counter-bob
	run_anim.track_insert_key(track_idx, 0.8, Vector3(0, 4.0, -0.5))
	
	# Head Rotation during Run (Keep it facing correctly)
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	run_anim.track_set_path(track_idx, "VisualRoot/Head:rotation")
	run_anim.track_insert_key(track_idx, 0.0, base_rot)
	run_anim.track_insert_key(track_idx, 0.8, base_rot)
	
	# Tail (Run) - bob and sway frantically
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	run_anim.track_set_path(track_idx, "VisualRoot/Tail:rotation")
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
		run_anim.track_set_path(track_idx, "VisualRoot/" + leg_name + ":rotation")
		run_anim.track_insert_key(track_idx, 0.0, Vector3(leg_swing_angle, 0, 0))
		run_anim.track_insert_key(track_idx, 0.4, Vector3(-leg_swing_angle, 0, 0))
		run_anim.track_insert_key(track_idx, 0.8, Vector3(leg_swing_angle, 0, 0))
		
	# Front Right & Back Left
	for leg_name in ["LegFR", "LegBL"]:
		track_idx = run_anim.add_track(Animation.TYPE_VALUE)
		run_anim.track_set_path(track_idx, "VisualRoot/" + leg_name + ":rotation")
		run_anim.track_insert_key(track_idx, 0.0, Vector3(-leg_swing_angle, 0, 0))
		run_anim.track_insert_key(track_idx, 0.4, Vector3(leg_swing_angle, 0, 0))
		run_anim.track_insert_key(track_idx, 0.8, Vector3(-leg_swing_angle, 0, 0))
	
	library.add_animation("Run", run_anim)
	
	# --- Rear Up Animation ---
	var rear_anim = Animation.new()
	rear_anim.length = 2.0 # 0.5 up, 1.0 hold, 0.5 down
	
	# Body: Rears back (Pitch up ~45 degrees)
	# Original Pos: (0, 2.5, 1), Rot: (-90, 180, 0) -> Quats or Euler
	# We animate "Body:rotation" directly. Base rotation is -90 deg on X, 180 on Y.
	# To rear up, we rotate further back on X.
	track_idx = rear_anim.add_track(Animation.TYPE_VALUE)
	rear_anim.track_set_path(track_idx, "VisualRoot/Body:rotation")
	var body_base_rot = Vector3(deg_to_rad(-90), deg_to_rad(180), 0)
	var body_rear_rot = Vector3(deg_to_rad(-135), deg_to_rad(180), 0) # Pitch up 45 deg
	
	rear_anim.track_insert_key(track_idx, 0.0, body_base_rot)
	rear_anim.track_insert_key(track_idx, 0.5, body_rear_rot)
	rear_anim.track_insert_key(track_idx, 1.5, body_rear_rot)
	rear_anim.track_insert_key(track_idx, 2.0, body_base_rot)
	
	# Body Position: Move up and back to simulate pivoting on rear legs
	track_idx = rear_anim.add_track(Animation.TYPE_VALUE)
	rear_anim.track_set_path(track_idx, "VisualRoot/Body:position")
	var body_base_pos = Vector3(0, 2.5, 1)
	var body_rear_pos = Vector3(0, 3.5, 1.5) # Lower (3.5) and further Back (1.5) to keep hips attached
	
	rear_anim.track_insert_key(track_idx, 0.0, body_base_pos)
	rear_anim.track_insert_key(track_idx, 0.5, body_rear_pos)
	rear_anim.track_insert_key(track_idx, 1.5, body_rear_pos)
	rear_anim.track_insert_key(track_idx, 2.0, body_base_pos)
	
	# Head: Adjust to look up/forward
	track_idx = rear_anim.add_track(Animation.TYPE_VALUE)
	rear_anim.track_set_path(track_idx, "VisualRoot/Head:rotation")
	# Base is (0, PI, 0).
	# Pitching UP (-45 deg) relative to body rearing
	var head_rear_rot = Vector3(deg_to_rad(-45), PI, 0)
	
	rear_anim.track_insert_key(track_idx, 0.0, base_rot)
	rear_anim.track_insert_key(track_idx, 0.5, head_rear_rot)
	rear_anim.track_insert_key(track_idx, 1.5, head_rear_rot)
	rear_anim.track_insert_key(track_idx, 2.0, base_rot)

	# Head Position: Needs to go way up and slightly back to follow body
	track_idx = rear_anim.add_track(Animation.TYPE_VALUE)
	rear_anim.track_set_path(track_idx, "VisualRoot/Head:position")
	var head_base_pos = Vector3(0, 4.0, -0.5)
	var head_rear_pos = Vector3(0, 5.5, -0.5) # Lower to stay attached to body
	
	rear_anim.track_insert_key(track_idx, 0.0, head_base_pos)
	rear_anim.track_insert_key(track_idx, 0.5, head_rear_pos)
	rear_anim.track_insert_key(track_idx, 1.5, head_rear_pos)
	rear_anim.track_insert_key(track_idx, 2.0, head_base_pos)
	
	# Tail (RearUp) - Continue wagging!
	track_idx = rear_anim.add_track(Animation.TYPE_VALUE)
	rear_anim.track_set_path(track_idx, "VisualRoot/Tail:rotation")
	# We'll do 2 quick wags during the 2s animation
	# Base rotation for tail needs to account for body rearing (Tail points down)
	var tail_rear_base = tail_base_rot + Vector3(deg_to_rad(45), 0, 0) # Adjust for body pitch
	
	rear_anim.track_insert_key(track_idx, 0.0, tail_base_rot)
	rear_anim.track_insert_key(track_idx, 0.2, tail_rear_base + Vector3(0, 0, deg_to_rad(30))) # Left
	rear_anim.track_insert_key(track_idx, 0.6, tail_rear_base + Vector3(0, 0, deg_to_rad(-30))) # Right
	rear_anim.track_insert_key(track_idx, 1.0, tail_rear_base + Vector3(0, 0, deg_to_rad(30))) # Left
	rear_anim.track_insert_key(track_idx, 1.4, tail_rear_base + Vector3(0, 0, deg_to_rad(-30))) # Right
	rear_anim.track_insert_key(track_idx, 1.8, tail_rear_base + Vector3(0, 0, deg_to_rad(30))) # Left
	rear_anim.track_insert_key(track_idx, 2.0, tail_base_rot)

	# Tail Position: Move up (slightly) and forward to follow body rearing
	track_idx = rear_anim.add_track(Animation.TYPE_VALUE)
	rear_anim.track_set_path(track_idx, "VisualRoot/Tail:position")
	var tail_base_pos = Vector3(0, 0.9, 1.8)
	var tail_rear_pos = Vector3(0, 1.8, 0.5) # Less Up (1.8 vs 3.0), still Forward (0.5)
	
	rear_anim.track_insert_key(track_idx, 0.0, tail_base_pos)
	rear_anim.track_insert_key(track_idx, 0.5, tail_rear_pos)
	rear_anim.track_insert_key(track_idx, 1.5, tail_rear_pos)
	rear_anim.track_insert_key(track_idx, 2.0, tail_base_pos)
	
	# Front Legs: Pivot from Shoulder (Top) and reach UP/FORWARD
	for leg_name in ["LegFL", "LegFR"]:
		track_idx = rear_anim.add_track(Animation.TYPE_VALUE)
		rear_anim.track_set_path(track_idx, "VisualRoot/" + leg_name + ":position")
		# Base position for Front Legs is z=-0.2
		var leg_base_pos = Vector3(1 if "FR" in leg_name else -1, 1, -0.2)
		# Position adjusted to simulate pivoting from the shoulder
		# Shoulder moves to approx Y=2.3, Z=1.0. Leg Center (radius offset) moves to Y=2.6, Z=0.0
		var leg_rear_pos = Vector3(1 if "FR" in leg_name else -1, 2.6, 0.0)
		
		rear_anim.track_insert_key(track_idx, 0.0, leg_base_pos)
		rear_anim.track_insert_key(track_idx, 0.5, leg_rear_pos)
		rear_anim.track_insert_key(track_idx, 1.5, leg_rear_pos)
		rear_anim.track_insert_key(track_idx, 2.0, leg_base_pos)
		
		track_idx = rear_anim.add_track(Animation.TYPE_VALUE)
		rear_anim.track_set_path(track_idx, "VisualRoot/" + leg_name + ":rotation")
		# Rotate +110 deg (Bottom points Front/Up). This simulates reaching up with hooves.
		var leg_rear_rot = Vector3(deg_to_rad(110), 0, 0) 
		
		rear_anim.track_insert_key(track_idx, 0.0, Vector3.ZERO)
		rear_anim.track_insert_key(track_idx, 0.5, leg_rear_rot)
		rear_anim.track_insert_key(track_idx, 1.5, leg_rear_rot)
		rear_anim.track_insert_key(track_idx, 2.0, Vector3.ZERO)

	library.add_animation("RearUp", rear_anim)
	
	# --- Dead Animation ---
	# Ensures legs are still when dead
	var dead_anim = Animation.new()
	dead_anim.loop_mode = Animation.LOOP_NONE
	dead_anim.length = 0.1
	
	for leg_name in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		track_idx = dead_anim.add_track(Animation.TYPE_VALUE)
		dead_anim.track_set_path(track_idx, "VisualRoot/" + leg_name + ":rotation")
		dead_anim.track_insert_key(track_idx, 0.0, Vector3.ZERO)
		
	library.add_animation("Dead", dead_anim)
	
	anim_player.add_animation_library("", library)
	anim_player.play("Idle")

func _process(delta):
	if is_dead: return
	
	# On clients (and Host), handle animation logic if physics_process is stopped or just for visual updates
	# But wait, physics_process handles animation on server.
	# The issue is likely that _process continues to run and might override animation on the Host.
	
	# Actually, let's simplify. If is_dead is true, we return early, so _process shouldn't run.
	# But maybe is_dead isn't true on the server?
	# die() is an RPC "call_local", so it should run on server.
	
	if not multiplayer.is_server():
		var current_pos = global_position
		if not has_meta("last_pos"): set_meta("last_pos", current_pos)
		var last_pos = get_meta("last_pos")
		var move_speed = current_pos.distance_to(last_pos) / delta
		set_meta("last_pos", current_pos)
		
		# If moving, reset the timeout and play run animation
		if move_speed > 0.1:
			run_timeout = 0.2 # Keep running for 0.2s after stopping
			# Only switch to Run if we aren't doing a special action
			if anim_player.current_animation != "Run" and anim_player.current_animation != "RearUp":
				anim_player.play("Run", 0.2)
		else:
			# If stopped, only switch to idle after timeout expires
			# This prevents flickering when network updates are sparse
			run_timeout -= delta
			if run_timeout <= 0:
				if anim_player.current_animation != "Idle" and anim_player.current_animation != "RearUp":
					anim_player.play("Idle", 0.2)

# Called by projectiles or rocks
func take_damage(amount):
	if is_dead: return
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
	# Robust check for death state to ensure no movement/animation runs after death
	if is_dead or health <= 0 or state == "dead":
		return
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Update target information
	player = find_nearest_player()

	if player:
		var dist = global_position.distance_to(player.global_position)
		
		# Change AI state based on how close the player is
		if dist < detection_radius:
			# If we weren't already chasing or rearing, start by rearing up!
			if state != "chase" and state != "rear_up":
				state = "rear_up"
				play_rearing_animation.rpc()
				# Set a timer to switch to chase after animation
				await get_tree().create_timer(2.0).timeout
				state = "chase"
		elif state == "chase" and dist > detection_radius * 1.5:
			state = "wander"
			
	# --- AI State Machine ---
	if state == "rear_up":
		# Don't move while rearing
		velocity = Vector3.ZERO
		
	elif state == "chase" and player:
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
		
		var horizontal_velocity = velocity
		horizontal_velocity.y = 0
		if horizontal_velocity.length() > 0.1:
			look_at(global_position + horizontal_velocity, Vector3.UP)

	# Execute the calculated movement
	move_and_slide()
	
	# Play animations based on movement only if NOT playing a prioritized action like RearUp
	if anim_player.current_animation != "RearUp":
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

# RPC to play the rear up animation on all clients
@rpc("call_local", "reliable")
func play_rearing_animation():
	if anim_player:
		anim_player.play("RearUp")

# RPC to handle Mammoth death across the network
@rpc("any_peer", "call_local", "reliable")
func die():
	if not is_inside_tree() or is_dead: return
	print("Mammoth Died!")
	is_dead = true
	state = "dead"
	
	# FIX: Stop all processing immediately to prevent any movement or animation overrides
	set_process(false)
	set_physics_process(false)
	velocity = Vector3.ZERO
	
	# FIX: Disable collisions immediately to prevents physics interactions
	collision_layer = 0
	collision_mask = 0
	
	# FIX: Disable the MultiplayerSynchronizer to stop rotation updates from server
	# colliding with our local death animation tween.
	var synchronizer = get_node_or_null("MultiplayerSynchronizer")
	if synchronizer:
		# queue_free() is deferred, so one last sync packet might slip through and reset rotation.
		# Setting config to null causes C++ errors.
		# BEST FIX: Set it to an empty config. This stops sync immediately and safely.
		synchronizer.replication_config = SceneReplicationConfig.new()
		synchronizer.queue_free()
	
	# Stop animation and force play "Dead"
	if anim_player:
		anim_player.stop()
		anim_player.play("Dead")
		
	# Disable all collision shapes
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true
			
	# FIX: Create a tween to rotate the visual model independently of the physics root.
	# This ensures that even if physics logic (like look_at) resets the root rotation,
	# the visual model stays fallen over.
	var tween = create_tween()
	# Rotate the VisualRoot around Z axis to make the mammoth fall on its side
	tween.tween_property(visual_root, "rotation:z", PI/2, 1.0).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
