# Generic AI Enemy for "Age of Manwe"
# This script handles basic AI behavior: wandering around and chasing players.
# In multiplayer, AI logic only runs on the Server to keep things consistent.
extends CharacterBody3D

# @export variables allow for easy balancing of enemy stats in the Editor
@export var speed = 4.0
@export var detection_radius = 15.0
@export var damage = 20
@export var max_health = 30.0 
@export var health = 30.0
@export var is_big = false # If true, this enemy becomes a "Big" variant

var is_dead = false
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var anim_player: AnimationPlayer

var player = null
var state = "wander"
var wander_target = Vector3.ZERO
var wander_timer = 0.0
var run_timeout = 0.0

func _ready():
	# Ensure the enemy only collides with Layer 1
	# and ignores Layer 2 (Grass), so they don't get stuck on grass patches.
	collision_mask = 1 
	
	create_cat_model()

	setup_animations()
	
	# Specialized setup for big enemies
	if is_big:
		max_health = 100.0
		health = 100.0
		speed = 2.5
		damage = 40
		scale = Vector3(2, 2, 2) # Make the model twice as large
		
	# --- MULTIPLAYER LOGIC ---
	# AI logic and movement calculations should ONLY run on the server.
	# Clients will see the enemy move because their position is synced via 
	# a MultiplayerSynchronizer node (not shown in this script, but in the scene).
	if not multiplayer.is_server():
		# Disable physics processing for clients to save CPU
		set_physics_process(false)

func setup_animations():
	anim_player = AnimationPlayer.new()
	add_child(anim_player)
	
	var library = AnimationLibrary.new()
	
	# --- Idle Animation ---
	var idle_anim = Animation.new()
	idle_anim.loop_mode = Animation.LOOP_LINEAR
	idle_anim.length = 2.0
	var track_idx = idle_anim.add_track(Animation.TYPE_VALUE)
	# Animate the new CatModel node instead of MeshInstance3D
	idle_anim.track_set_path(track_idx, "CatModel:scale")
	idle_anim.track_insert_key(track_idx, 0.0, Vector3(1, 1, 1))
	idle_anim.track_insert_key(track_idx, 1.0, Vector3(1.05, 0.95, 1.05)) # Breathing effect
	idle_anim.track_insert_key(track_idx, 2.0, Vector3(1, 1, 1))
	library.add_animation("Idle", idle_anim)
	
	# --- Run Animation ---
	var run_anim = Animation.new()
	run_anim.loop_mode = Animation.LOOP_LINEAR
	run_anim.length = 0.4
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	# Animate position for hopping
	run_anim.track_set_path(track_idx, "CatModel:position")
	run_anim.track_insert_key(track_idx, 0.0, Vector3(0, 0, 0))
	run_anim.track_insert_key(track_idx, 0.2, Vector3(0, 0.2, 0)) # Small hop
	run_anim.track_insert_key(track_idx, 0.4, Vector3(0, 0, 0))
	
	# Add rotation for running motion
	track_idx = run_anim.add_track(Animation.TYPE_VALUE)
	run_anim.track_set_path(track_idx, "CatModel:rotation")
	run_anim.track_insert_key(track_idx, 0.0, Vector3(0, 0, deg_to_rad(-5)))
	run_anim.track_insert_key(track_idx, 0.2, Vector3(0, 0, deg_to_rad(5)))
	run_anim.track_insert_key(track_idx, 0.4, Vector3(0, 0, deg_to_rad(-5)))
	
	library.add_animation("Run", run_anim)
	
	anim_player.add_animation_library("", library)
	anim_player.play("Idle")

func _process(delta):
	if is_dead: return
	# On clients, we need to check if the enemy is moving to play animations
	# since physics_process is disabled.
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
			run_timeout -= delta
			if run_timeout <= 0:
				if anim_player.current_animation != "Idle":
					anim_player.play("Idle", 0.2)

# Creates a long slender cat model
func create_cat_model():
	# Hide existing meshes if they exist
	if has_node("MeshInstance3D"): $MeshInstance3D.visible = false
	if has_node("EyeLeft"): $EyeLeft.visible = false
	if has_node("EyeRight"): $EyeRight.visible = false

	# Create a parent node for the cat model so we can animate it easily
	var cat_root = Node3D.new()
	cat_root.name = "CatModel"
	add_child(cat_root)

	# --- Materials ---
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.1, 0.1, 0.1) # Black cat
	
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1, 1, 0) # Yellow eyes
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.5, 0.5, 0)

	# --- Body (Long Cylinder) ---
	var body = MeshInstance3D.new()
	var body_mesh = CylinderMesh.new()
	body_mesh.top_radius = 0.15
	body_mesh.bottom_radius = 0.15
	body_mesh.height = 1.2
	body.mesh = body_mesh
	body.material_override = body_mat
	# Rotate body to be horizontal
	body.rotation.x = deg_to_rad(90)
	body.position.y = 0.5
	cat_root.add_child(body)

	# --- Head (Sphere) ---
	var head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.25
	head_mesh.height = 0.5
	head.mesh = head_mesh
	head.material_override = body_mat
	head.position = Vector3(0, 0.7, -0.7) # Position at front of body
	cat_root.add_child(head)

	# --- Ears (Cones) ---
	for i in [-1, 1]:
		var ear = MeshInstance3D.new()
		var ear_mesh = CylinderMesh.new()
		ear_mesh.top_radius = 0.0
		ear_mesh.bottom_radius = 0.08
		ear_mesh.height = 0.2
		ear.mesh = ear_mesh
		ear.material_override = body_mat
		ear.position = Vector3(i * 0.15, 0.9, -0.7)
		cat_root.add_child(ear)

	# --- Eyes ---
	for i in [-1, 1]:
		var eye = MeshInstance3D.new()
		var eye_mesh = SphereMesh.new()
		eye_mesh.radius = 0.05
		eye_mesh.height = 0.1
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(i * 0.1, 0.75, -0.9)
		cat_root.add_child(eye)

	# --- Legs (4 Cylinders) ---
	var leg_positions = [
		Vector3(-0.15, 0.25, -0.4), # Front Left
		Vector3(0.15, 0.25, -0.4),  # Front Right
		Vector3(-0.15, 0.25, 0.4),  # Back Left
		Vector3(0.15, 0.25, 0.4)    # Back Right
	]
	
	for pos in leg_positions:
		var leg = MeshInstance3D.new()
		var leg_mesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.05
		leg_mesh.bottom_radius = 0.05
		leg_mesh.height = 0.5
		leg.mesh = leg_mesh
		leg.material_override = body_mat
		leg.position = pos
		cat_root.add_child(leg)

	# --- Tail (Long Thin Cylinder) ---
	var tail = MeshInstance3D.new()
	var tail_mesh = CylinderMesh.new()
	tail_mesh.top_radius = 0.04
	tail_mesh.bottom_radius = 0.02
	tail_mesh.height = 0.8
	tail.mesh = tail_mesh
	tail.material_override = body_mat
	# Angle tail up and back
	tail.position = Vector3(0, 0.8, 0.7)
	tail.rotation.x = deg_to_rad(-45)
	cat_root.add_child(tail)

# Called when hit by a projectile
func take_damage(amount):
	if is_dead: return
	# Only the server should manage enemy health
	if not multiplayer.is_server(): return
	
	health -= amount
	if health <= 0:
		# Trigger the explode RPC so all clients see the death effect
		explode.rpc()

# Helper function to find the closest player in the world
func find_nearest_player():
	var nearest = null
	var min_dist = INF
	# Iterate through all siblings of the enemy (assumed to be where players are)
	for node in get_parent().get_children():
		# In this project, players are named with their Peer ID (an integer)
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
	if is_dead: return
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# AI Target finding
	player = find_nearest_player()

	if player:
		var dist = global_position.distance_to(player.global_position)
		# Switch states based on distance to player
		if dist < detection_radius:
			state = "chase"
		elif state == "chase" and dist > detection_radius * 1.5:
			state = "wander"
			
	# --- AI State Machine ---
	if state == "chase" and player:
		# Move towards the player
		var direction = (player.global_position - global_position).normalized()
		direction.y = 0 
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# Rotate to face the player
		var target_pos = Vector3(player.global_position.x, global_position.y, player.global_position.z)
		if global_position.distance_squared_to(target_pos) > 0.1:
			look_at(target_pos, Vector3.UP)
		
	elif state == "wander":
		# Wander around randomly
		wander_timer -= delta
		if wander_timer <= 0:
			# Pick a new random target point every few seconds
			wander_timer = randf_range(2.0, 5.0)
			var random_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			wander_target = global_position + random_dir * 10.0
		
		var direction = (wander_target - global_position).normalized()
		velocity.x = direction.x * speed * 0.5 # Wander at half speed
		velocity.z = direction.z * speed * 0.5
		
		if velocity.length() > 0.1:
			var look_target = global_position + velocity
			if not global_position.is_equal_approx(look_target) and Vector3.UP.cross(velocity).length_squared() > 0.001:
				look_at(look_target, Vector3.UP)

	# Actually move the enemy
	move_and_slide()
	
	if velocity.length() > 0.1:
		anim_player.play("Run")
	else:
		anim_player.play("Idle")
	
	# --- Damage Dealing Logic ---
	# Check if we collided with anything during move_and_slide()
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var body = collision.get_collider()
		# If the thing we hit is a player (integer name), deal damage
		if body.has_method("take_damage") and body.name.is_valid_int():
			# We MUST call .rpc() here so the client player knows they got hit!
			# delta is used so damage is "per second"
			body.take_damage.rpc(damage * delta)

# RPC for the death effect. "call_local" means it runs on server + all clients.
@rpc("any_peer", "call_local", "reliable")
func explode():
	if not is_inside_tree() or is_dead: return
	print("Enemy Exploded!")
	is_dead = true
	spawn_particles()
	
	# Disable collision
	$CollisionShape3D.disabled = true
	
	# Stop animation
	if anim_player:
		anim_player.stop()
	
	# Fall over animation (rotate 90 degrees sideways)
	var tween = create_tween()
	tween.tween_property(self, "rotation:z", rotation.z + PI/2, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

# Visual effect for enemy death
func spawn_particles():
	var particles = CPUParticles3D.new()
	get_tree().root.add_child(particles) # Add to root so they stay after enemy is gone
	particles.global_position = global_position
	
	# Particle settings for a "blood burst" effect
	particles.emitting = true
	particles.amount = 30
	particles.lifetime = 1.0
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.spread = 180.0
	particles.gravity = Vector3(0, -10, 0)
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 10.0
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.5
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0) # Red
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0, 0)
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.3)
	mesh.material = mat
	particles.mesh = mesh
	
	# Automatically clean up the particles after they finish
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()
