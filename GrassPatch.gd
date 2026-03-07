# Flammable Grass Logic for "Age of Manwe"
#
# This script handles grass patches that can be ignited by Fire Spears.
# Once lit, the fire spreads to nearby grass patches and damages players/enemies standing in it.
#
# Network Architecture:
# - Grass patches are spawned by the World generator (Server) and synced via MultiplayerSpawner.
# - Fire state (`is_lit`) is synced via RPC `ignite()`.
# - Damage and Fire Spreading logic run ONLY on the Server to prevent double-damage/cheating.

extends StaticBody3D

# --- Configuration ---
@onready var fire_particles = $CPUParticles3D
@export var is_lit: bool = false
var dps: float = 25.0              # Damage Per Second to entities in fire
var spread_timer: float = 0.0
var spread_interval: float = 0.5   # Check for spread every 0.5 seconds
var spread_chance: float = 0.1     # 10% chance to spread per check per neighbor

# --- Collision Areas ---
var damage_area: Area3D            # Detects entities standing IN the fire
var spread_area: Area3D            # Detects neighbor grass patches slightly OUTSIDE

# --------------------------------------------------------------------------------------------------
# INITIALIZATION
# --------------------------------------------------------------------------------------------------

func _ready():
	# Configure Collision Layers
	# Layer 2 = Grass. Mask 0 = Doesn't collide with anything physically.
	# This makes grass "intangible" to players (Layer 1) but detectable by other systems looking at Layer 2.
	collision_layer = 2 
	collision_mask = 0
	
	# Setup detection areas
	setup_damage_area()
	setup_spread_area()
	
	# Initialize State
	if is_lit:
		fire_particles.emitting = true
		set_process(true)
	else:
		fire_particles.emitting = false
		set_process(false) # Disable _process to save CPU when not burning

func setup_damage_area():
	damage_area = Area3D.new()
	add_child(damage_area)
	
	var collision_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(2, 1, 2) # Size of the grass patch
	collision_shape.shape = box
	collision_shape.position.y = 0.5
	damage_area.add_child(collision_shape)

func setup_spread_area():
	spread_area = Area3D.new()
	spread_area.name = "SpreadArea"
	add_child(spread_area)
	
	var collision_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(3.5, 1, 3.5) # Larger than damage area to reach neighbors
	collision_shape.shape = box
	collision_shape.position.y = 0.5
	spread_area.add_child(collision_shape)
	
	# Only detect other grass patches (Layer 2)
	spread_area.collision_mask = 2
	spread_area.monitorable = false # We only want to detect, not be detected by this specific area

# --------------------------------------------------------------------------------------------------
# BURNING LOGIC (Server Only)
# --------------------------------------------------------------------------------------------------

func _process(delta):
	if not is_lit: return
	
	# Security: Only Server calculates damage and fire spread
	if not multiplayer.is_server(): return
	
	# 1. Deal Damage to everything in the fire
	for body in damage_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			# If it's a Player (Peer ID name)
			if body.name.is_valid_int():
				body.take_damage.rpc(dps * delta)
			# If it's an AI (Mammoth/Enemy)
			else:
				body.take_damage(dps * delta)
				
	# 2. Spread Fire to neighbors
	spread_timer += delta
	if spread_timer >= spread_interval:
		spread_timer = 0.0
		attempt_spread_fire()

func attempt_spread_fire():
	for body in spread_area.get_overlapping_bodies():
		if body == self: continue # Don't ignite self
		
		# If neighbor is flammable and not yet lit
		if body.has_method("ignite") and not body.is_lit:
			# Roll dice for spread
			if randf() < spread_chance:
				body.ignite.rpc()

# --------------------------------------------------------------------------------------------------
# NETWORKED ACTIONS
# --------------------------------------------------------------------------------------------------

# RPC: Lights this grass patch on fire on all clients.
@rpc("call_local", "reliable")
func ignite():
	if is_lit: return
	is_lit = true
	fire_particles.emitting = true
	set_process(true) # Enable the update loop
