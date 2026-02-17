extends CharacterBody3D

var speed = 4.0
var detection_radius = 15.0
var damage = 20
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var player = null
var state = "wander"
var wander_target = Vector3.ZERO
var wander_timer = 0.0

func _ready():
	# Only server runs AI logic
	if not multiplayer.is_server():
		set_physics_process(false)
		return

func find_nearest_player():
	var nearest = null
	var min_dist = INF
	# Assume players are children of World and named with IDs or in a group
	# Or just iterate all CharacterBody3D that are players
	for node in get_parent().get_children():
		if node is CharacterBody3D and node.name.is_valid_int(): # Simple check for player ID names
			var dist = global_position.distance_to(node.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = node
	return nearest

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	player = find_nearest_player()

	if player:
		var dist = global_position.distance_to(player.global_position)
		if dist < detection_radius:
			state = "chase"
		elif state == "chase" and dist > detection_radius * 1.5:
			state = "wander"
			
	if state == "chase" and player:
		var direction = (player.global_position - global_position).normalized()
		direction.y = 0 # Keep movement on ground plane
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		var target_pos = Vector3(player.global_position.x, global_position.y, player.global_position.z)
		if global_position.distance_squared_to(target_pos) > 0.1:
			look_at(target_pos, Vector3.UP)
		
	elif state == "wander":
		wander_timer -= delta
		if wander_timer <= 0:
			wander_timer = randf_range(2.0, 5.0)
			# Pick a random point nearby
			var random_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			wander_target = global_position + random_dir * 10.0
		
		var direction = (wander_target - global_position).normalized()
		velocity.x = direction.x * speed * 0.5 # Slower wander
		velocity.z = direction.z * speed * 0.5
		
		if velocity.length() > 0.1:
			look_at(global_position + velocity, Vector3.UP)

	move_and_slide()
	
	# Handle Collision with Player
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var body = collision.get_collider()
		if body.name == "Player" or body.has_method("take_damage"):
			if body.has_method("take_damage"):
				body.take_damage(damage * delta) # Continuous damage or needs cooldown?
				# Let's do a simple knockback or just damage per frame (dangerous if high fps)
				# 20 damage * delta means 20 damage per second. That's reasonable.

@rpc("any_peer", "call_local", "reliable")
func explode():
	# Called by Spear via RPC
	print("Enemy Exploded!")
	spawn_particles()
	queue_free()

func spawn_particles():
	var particles = CPUParticles3D.new()
	# Add to root or world so it doesn't get deleted with enemy
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	
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
	mat.albedo_color = Color(1, 0, 0) # Red Blood/Explosion
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0, 0)
	
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.3)
	mesh.material = mat
	particles.mesh = mesh
	
	# Auto cleanup particles
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()
