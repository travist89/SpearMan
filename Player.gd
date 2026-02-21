extends CharacterBody3D

@export var speed = 5.0
@export var sprint_speed = 10.0
@export var jump_velocity = 4.5
@export var mouse_sensitivity = 0.003
@export var throw_force = 45.0
@export var spear_scene: PackedScene
@export var rock_scene: PackedScene = preload("res://Rock.tscn")

# Weapon System
var weapons = ["Spear", "Rock"]
var weapon_index = 0
var last_throw_time = 0.0
var throw_cooldown = 0.5

# Stats
@export var max_health = 100.0
@export var health = 100.0
@export var max_stamina = 100.0
@export var stamina = 100.0

var stamina_drain = 30.0 
var stamina_regen = 15.0 
var speed_boost_multiplier = 1.0
var speed_boost_time = 0.0
var is_dead = false

# UI Elements
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var weapon_label: Label

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera_pivot = $CameraPivot
@onready var camera = $CameraPivot/SpringArm3D/Camera3D
@onready var hand_position = $HandPosition 

func _enter_tree():
	var id = name.to_int()
	if id == 0: id = 1 
	set_multiplayer_authority(id)

func _ready():
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		camera.current = true
		setup_ui()
	else:
		camera.current = false

func setup_ui():
	if not is_multiplayer_authority(): return
	var canvas_layer = CanvasLayer.new(); add_child(canvas_layer)
	
	health_bar = ProgressBar.new(); canvas_layer.add_child(health_bar)
	health_bar.position = Vector2(20, 20); health_bar.size = Vector2(200, 20); health_bar.max_value = max_health; health_bar.value = health; health_bar.modulate = Color(1, 0, 0)
	
	stamina_bar = ProgressBar.new(); canvas_layer.add_child(stamina_bar)
	stamina_bar.position = Vector2(20, 50); stamina_bar.size = Vector2(200, 20); stamina_bar.max_value = max_stamina; stamina_bar.value = stamina; stamina_bar.modulate = Color(0, 1, 0)
	
	weapon_label = Label.new(); canvas_layer.add_child(weapon_label)
	weapon_label.position = Vector2(20, 80); update_weapon_ui()

func update_weapon_ui():
	if weapon_label:
		weapon_label.text = "Weapon: " + weapons[weapon_index] + " (Press 1 or 2 to switch)"

func take_damage(amount):
	if is_dead: return
	health -= amount
	if health_bar: health_bar.value = health
	if health <= 0: die()

func restore_health(amount):
	if is_dead: return
	health = min(health + amount, max_health)
	if health_bar: health_bar.value = health

func apply_speed_boost(multiplier, duration):
	speed_boost_multiplier = multiplier; speed_boost_time = duration

func die():
	if is_dead: return
	is_dead = true; if is_multiplayer_authority(): respawn.rpc()

@rpc("any_peer", "call_local", "reliable")
func respawn():
	is_dead = false; health = max_health
	if health_bar: health_bar.value = health
	global_position = Vector3(0, 30, 0); velocity = Vector3.ZERO

func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.2, 1.2)
		
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	if event.is_action_pressed("click"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif Time.get_ticks_msec() / 1000.0 - last_throw_time > throw_cooldown:
			last_throw_time = Time.get_ticks_msec() / 1000.0
			throw_projectile.rpc(weapon_index)
			
	# Weapon Switching
	if Input.is_key_pressed(KEY_1):
		weapon_index = 0; update_weapon_ui()
	if Input.is_key_pressed(KEY_2):
		weapon_index = 1; update_weapon_ui()

func _physics_process(delta):
	if not is_multiplayer_authority():
		# For non-local players, position is synced by MultiplayerSynchronizer.
		# We still call move_and_slide() to ensure physics/collision state is updated,
		# but we don't apply gravity or input forces locally.
		move_and_slide()
		return

	if is_dead: return
	if not is_on_floor(): velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor(): velocity.y = jump_velocity
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	if input_dir.length() > 1.0: input_dir = input_dir.normalized()
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if speed_boost_time > 0:
		speed_boost_time -= delta
		if speed_boost_time <= 0: speed_boost_multiplier = 1.0
	var current_speed = speed * speed_boost_multiplier
	if Input.is_key_pressed(KEY_SHIFT) and direction.length() > 0 and stamina > 0:
		current_speed = sprint_speed * speed_boost_multiplier; stamina -= stamina_drain * delta
	else: stamina += stamina_regen * delta
	stamina = clamp(stamina, 0, max_stamina)
	if stamina_bar: stamina_bar.value = stamina
	if direction: velocity.x = direction.x * current_speed; velocity.z = direction.z * current_speed
	else: velocity.x = move_toward(velocity.x, 0, current_speed); velocity.z = move_toward(velocity.z, 0, current_speed)
	move_and_slide()

@rpc("any_peer", "call_local")
func throw_projectile(type):
	if not multiplayer.is_server(): return
	
	var projectile_scene = spear_scene
	if type == 1:
		projectile_scene = rock_scene
		
	if projectile_scene:
		var p = projectile_scene.instantiate()
		get_parent().add_child(p, true)
		p.global_transform = hand_position.global_transform
		var camera_forward = -camera.global_transform.basis.z
		p.look_at(p.global_position + camera_forward, Vector3.UP)
		p.apply_impulse(-p.global_transform.basis.z * throw_force)
