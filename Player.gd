# Main Player Controller for "Age of Manwe"
# This script handles everything a player can do: moving, looking around, jumping, 
# shooting projectiles, taking damage, and dying. It also handles networking
# to ensure players see each other correctly in multiplayer.
extends CharacterBody3D

# @export variables are visible in the Godot Editor inspector, 
# making it easy to tweak values without changing code.
@export var speed = 5.0
@export var sprint_speed = 10.0
@export var jump_velocity = 10.0
@export var mouse_sensitivity = 0.003
@export var throw_force = 45.0
@export var spear_scene: PackedScene # Reference to the Spear prefab
@export var rock_scene: PackedScene = preload("res://Rock.tscn") # Preloads the Rock prefab

# --- Player State Variables ---
var weapons = ["Spear", "Rock"]
var weapon_index = 0
var last_throw_time = 0.0
var throw_cooldown = 0.5

@export var max_health = 100.0
@export var health = 100.0
@export var max_stamina = 100.0
@export var stamina = 100.0

var stamina_drain = 30.0 
var stamina_regen = 15.0 
var speed_boost_multiplier = 1.0
var speed_boost_time = 0.0
var is_dead = false

# UI references (only created for the local player)
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var weapon_label: Label

# Get the gravity setting from the project settings so it matches the rest of the game
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# @onready variables are initialized when the node enters the scene tree for the first time
@onready var camera_pivot = $CameraPivot
@onready var camera = $CameraPivot/SpringArm3D/Camera3D
@onready var hand_position = $HandPosition 

# _enter_tree is called when the node is added to the scene. 
# In multiplayer, we use the node name (set to Peer ID) to determine who controls this player.
func _enter_tree():
	# name.to_int() converts the peer ID (like "1" or "123456") to an integer
	var id = name.to_int()
	if id == 0: id = 1 # Peer ID 1 is always the Host/Server
	# set_multiplayer_authority tells Godot which peer is "in charge" of this node.
	# Usually, each player controls their own character.
	set_multiplayer_authority(id)

# _ready is called after the node and all its children have entered the scene tree.
func _ready():
	# is_multiplayer_authority() check ensures only YOU control YOUR player.
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # Lock mouse to center of screen
		camera.current = true # Use this player's camera
		setup_ui()
	else:
		# If this is someone else's player, don't use their camera!
		camera.current = false

# Dynamically creates a simple 2D UI for health and stamina
func setup_ui():
	if not is_multiplayer_authority(): return
	
	var canvas_layer = CanvasLayer.new() 
	add_child(canvas_layer)
	
	health_bar = ProgressBar.new()
	canvas_layer.add_child(health_bar)
	health_bar.position = Vector2(20, 20)
	health_bar.size = Vector2(200, 20)
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.modulate = Color(1, 0, 0) # Red color
	
	stamina_bar = ProgressBar.new()
	canvas_layer.add_child(stamina_bar)
	stamina_bar.position = Vector2(20, 50)
	stamina_bar.size = Vector2(200, 20)
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	stamina_bar.modulate = Color(0, 1, 0) # Green color
	
	weapon_label = Label.new()
	canvas_layer.add_child(weapon_label)
	weapon_label.position = Vector2(20, 80)
	update_weapon_ui()

func update_weapon_ui():
	if weapon_label:
		weapon_label.text = "Weapon: " + weapons[weapon_index] + " (Press 1 or 2 to switch)"

# @rpc marks this function as a Remote Procedure Call.
# "any_peer" means any player can call it (needed for server to call it on clients).
# "call_local" means it also runs on the machine that called it.
# "reliable" means the network ensures it arrives (slower but safer).
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount):
	if is_dead: return
	health -= amount
	# Only the owner of the player has a health_bar reference
	if health_bar: health_bar.value = health
	if health <= 0: die()

func restore_health(amount):
	if is_dead: return
	health = min(health + amount, max_health)
	if health_bar: health_bar.value = health

func apply_speed_boost(multiplier, duration):
	speed_boost_multiplier = multiplier
	speed_boost_time = duration

# When a player dies, they tell everyone they are dead and request a respawn.
func die():
	if is_dead: return
	is_dead = true
	# Only the owner of the player initiates the respawn RPC
	if is_multiplayer_authority(): 
		respawn.rpc()

@rpc("any_peer", "call_local", "reliable")
func respawn():
	is_dead = false
	health = max_health
	if health_bar: health_bar.value = health
	# Move player back to a starting position
	global_position = Vector3(0, 30, 0)
	velocity = Vector3.ZERO

# Handles mouse movement and keyboard shortcuts for non-movement actions
func _unhandled_input(event):
	# Optimization: Only the local player should process their own mouse/input.
	if not is_multiplayer_authority(): return
	
	# Rotate camera based on mouse movement
	if event is InputEventMouseMotion:
		# Rotate the player horizontally (Left/Right)
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Rotate the camera pivot vertically (Up/Down)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		# Limit vertical rotation so the camera doesn't flip over
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.2, 1.2)
		
	# Press Esc to show mouse cursor
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	# Left click to attack
	if event.is_action_pressed("click"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			# Re-capture mouse if clicking back into the game
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif Time.get_ticks_msec() / 1000.0 - last_throw_time > throw_cooldown:
			# Enforce a cooldown between throws
			last_throw_time = Time.get_ticks_msec() / 1000.0
			# Call the RPC on the server to spawn the projectile
			throw_projectile.rpc(weapon_index)
			
	# Weapon Switching
	if Input.is_key_pressed(KEY_1):
		weapon_index = 0
		update_weapon_ui()
	if Input.is_key_pressed(KEY_2):
		weapon_index = 1
		update_weapon_ui()

# _physics_process is called every physics frame (usually 60 times per second)
func _physics_process(delta):
	# --- MULTIPLAYER OPTIMIZATION ---
	# We only want to run movement logic for the machine that OWNS this player.
	if not is_multiplayer_authority():
		# For other players, we just call move_and_slide() so their collisions 
		# still work correctly in the physics world, but we don't calculate movement.
		move_and_slide()
		return

	if is_dead: return

	# Apply Gravity if not on the floor
	if not is_on_floor(): 
		velocity.y -= gravity * delta

	# Handle Jumping
	if Input.is_action_just_pressed("ui_accept") and is_on_floor(): 
		velocity.y = jump_velocity

	# Get input direction from keyboard (WASD or Arrow Keys)
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# Manual keyboard checks as fallback or project-specific controls
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	
	# Normalize to ensure diagonal movement isn't faster
	if input_dir.length() > 1.0: 
		input_dir = input_dir.normalized()
	
	# Calculate move direction relative to where the player is facing
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Handle Speed Boost duration
	if speed_boost_time > 0:
		speed_boost_time -= delta
		if speed_boost_time <= 0: 
			speed_boost_multiplier = 1.0
	
	# Calculate Sprinting and Stamina
	var current_speed = speed * speed_boost_multiplier
	if Input.is_key_pressed(KEY_SHIFT) and direction.length() > 0 and stamina > 0:
		current_speed = sprint_speed * speed_boost_multiplier
		stamina -= stamina_drain * delta # Drain stamina while sprinting
	else: 
		stamina += stamina_regen * delta # Regen stamina when not sprinting
	
	stamina = clamp(stamina, 0, max_stamina)
	if stamina_bar: stamina_bar.value = stamina
	
	# Apply movement to velocity
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		# Slow down smoothly when no input is given
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# move_and_slide handles collisions and sliding along walls automatically
	move_and_slide()

# Server-side logic for spawning projectiles
# Spawning objects MUST be done on the server to ensure everyone sees the same thing.
@rpc("any_peer", "call_local")
func throw_projectile(type):
	# Security: Only the server is allowed to actually instantiate nodes.
	if not multiplayer.is_server(): return
	
	var projectile_scene = spear_scene
	if type == 1:
		projectile_scene = rock_scene
		
	if projectile_scene:
		var p = projectile_scene.instantiate()
		
		# Add projectile to the World (parent) so it's independent of the player's movement
		get_parent().add_child(p, true) # 'true' makes it a networked node
		
		# Set projectile position to the player's hand
		p.global_transform = hand_position.global_transform
		
		# Make the projectile face where the camera is looking
		var camera_forward = -camera.global_transform.basis.z
		p.look_at(p.global_position + camera_forward, Vector3.UP)
		
		# If the projectile is a physics body, launch it!
		if p is RigidBody3D:
			p.apply_impulse(-p.global_transform.basis.z * throw_force)
