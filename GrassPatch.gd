extends StaticBody3D

@onready var fire_particles = $CPUParticles3D
@export var is_lit = false
var damage_area: Area3D
var dps = 25.0
var spread_timer = 0.0
var spread_interval = 0.5 # Check for spread every 0.5 seconds
var spread_chance = 0.1 # 10% chance to spread per check
var spread_area: Area3D

func _ready():
	# Set collision layer to 2 (Grass) and mask to 0 (don't collide with anything)
	# This effectively makes it intangible to players (Layer 1) but still detectable if we check Layer 2
	collision_layer = 2 
	collision_mask = 0
	
	setup_damage_area()
	setup_spread_area()
	
	if is_lit:
		fire_particles.emitting = true
		set_process(true)
	else:
		fire_particles.emitting = false
		set_process(false)

func setup_damage_area():
	damage_area = Area3D.new()
	add_child(damage_area)
	
	var collision_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(2, 1, 2)
	collision_shape.shape = box
	collision_shape.position.y = 0.5
	damage_area.add_child(collision_shape)

func setup_spread_area():
	spread_area = Area3D.new()
	spread_area.name = "SpreadArea"
	add_child(spread_area)
	
	var collision_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(3.5, 1, 3.5) # Slightly larger than damage area to reach neighbors
	collision_shape.shape = box
	collision_shape.position.y = 0.5
	spread_area.add_child(collision_shape)
	
	# Detect other grass patches (Layer 2)
	spread_area.collision_mask = 2
	spread_area.monitorable = false # We only want to detect, not be detected by this area

func _process(delta):
	if not is_lit: return
	
	# Only the server handles logic
	if not multiplayer.is_server(): return
	
	# Damage logic
	for body in damage_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			if body.name.is_valid_int():
				# It's a player (Peer ID name), use RPC
				body.take_damage.rpc(dps * delta)
			elif body.has_method("find_nearest_player"):
				# It's an Enemy or Mammoth, call directly on server
				body.take_damage(dps * delta)
				
	# Fire spreading logic
	spread_timer += delta
	if spread_timer >= spread_interval:
		spread_timer = 0.0
		attempt_spread_fire()

func attempt_spread_fire():
	for body in spread_area.get_overlapping_bodies():
		if body == self: continue
		if body.has_method("ignite") and not body.is_lit:
			if randf() < spread_chance:
				body.ignite.rpc()

@rpc("call_local")
func ignite():
	if is_lit: return
	is_lit = true
	fire_particles.emitting = true
	set_process(true)
