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

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var player = null
var state = "wander"
var wander_target = Vector3.ZERO
var wander_timer = 0.0

func _ready():
	# Specialized setup for big enemies
	if is_big:
		max_health = 100.0
		health = 100.0
		speed = 2.5
		damage = 40
		scale = Vector3(2, 2, 2) # Make the model twice as large
		create_legs()
		
	# --- MULTIPLAYER LOGIC ---
	# AI logic and movement calculations should ONLY run on the server.
	# Clients will see the enemy move because their position is synced via 
	# a MultiplayerSynchronizer node (not shown in this script, but in the scene).
	if not multiplayer.is_server():
		# Disable physics processing for clients to save CPU
		set_physics_process(false)
		return

# Programmatically creates legs for the big enemy variant
func create_legs():
	for i in range(4):
		var leg = MeshInstance3D.new()
		var leg_mesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.1
		leg_mesh.bottom_radius = 0.1
		leg_mesh.height = 1.5
		leg.mesh = leg_mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.2)
		leg.material_override = mat
		
		add_child(leg)
		
		# Position legs at corners using basic trigonometry
		var angle = (PI/2) * i + (PI/4)
		leg.position = Vector3(cos(angle) * 0.4, -0.5, sin(angle) * 0.4)
		# Slightly tilt the legs for a better look
		leg.rotation.z = deg_to_rad(15) if cos(angle) > 0 else deg_to_rad(-15)

# Called when hit by a projectile
func take_damage(amount):
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
			var dist = global_position.distance_to(node.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = node
	return nearest

func _physics_process(delta):
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
			look_at(global_position + velocity, Vector3.UP)

	# Actually move the enemy
	move_and_slide()
	
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
	if not is_inside_tree(): return
	print("Enemy Exploded!")
	spawn_particles()
	queue_free() # Remove the enemy from the game

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
