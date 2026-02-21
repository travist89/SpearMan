extends CharacterBody3D

@export var speed = 2.0
@export var run_speed = 6.0
@export var detection_radius = 20.0
@export var flee_radius = 15.0
@export var max_health = 200.0
@export var health = 200.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var player = null
var state = "wander"
var wander_target = Vector3.ZERO
var wander_timer = 0.0

func _ready():
	if not multiplayer.is_server():
		set_physics_process(false)
		return

func take_damage(amount):
	if not multiplayer.is_server(): return
	health -= amount
	# Spook the mammoth when damaged
	state = "flee"
	if health <= 0:
		die.rpc()

func find_nearest_player():
	var nearest = null
	var min_dist = INF
	for node in get_parent().get_children():
		if node is CharacterBody3D and node.name.is_valid_int():
			var dist = global_position.distance_to(node.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = node
	return nearest

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	player = find_nearest_player()

	if player:
		var dist = global_position.distance_to(player.global_position)
		
		# If fleeing, keep fleeing until far enough
		if state == "flee":
			if dist > flee_radius * 2.0:
				state = "wander"
		# If wandering and player gets too close, maybe get annoyed or flee?
		# For now, mammoths are peaceful unless provoked or very close
		elif dist < 5.0:
			state = "flee"
			
	if state == "flee" and player:
		# Run away from player
		var direction = (global_position - player.global_position).normalized()
		direction.y = 0 
		velocity.x = direction.x * run_speed
		velocity.z = direction.z * run_speed
		
		if velocity.length() > 0.1:
			look_at(global_position + velocity, Vector3.UP)
		
	elif state == "wander":
		wander_timer -= delta
		if wander_timer <= 0:
			wander_timer = randf_range(5.0, 10.0) # Move less often
			var random_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			wander_target = global_position + random_dir * 15.0
		
		var direction = (wander_target - global_position).normalized()
		# Stop if close to target
		if global_position.distance_to(wander_target) < 1.0:
			velocity.x = 0
			velocity.z = 0
		else:
			velocity.x = direction.x * speed 
			velocity.z = direction.z * speed
		
		if velocity.length() > 0.1:
			look_at(global_position + velocity, Vector3.UP)

	move_and_slide()

@rpc("any_peer", "call_local", "reliable")
func die():
	# TODO: Spawn meat chunks for harvesting instead of just disappearing
	print("Mammoth Died!")
	# For now, just play a death effect or ragdoll (not implemented)
	queue_free()
