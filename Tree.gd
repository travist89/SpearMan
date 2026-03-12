# Flammable Tree Logic for "Age of Manwe"
extends StaticBody3D

@onready var fire_particles = $CPUParticles3D
@onready var fire_light = $FireLight
@export var is_lit: bool = false

func _ready():
	# Collision Layer 2: Environment/Grass
	collision_layer = 2 
	collision_mask = 0
	
	if is_lit:
		fire_particles.emitting = true
		fire_light.visible = true
	else:
		fire_particles.emitting = false
		fire_light.visible = false

@rpc("call_local", "reliable")
func ignite():
	if is_lit: return
	is_lit = true
	fire_particles.emitting = true
	fire_light.visible = true
	
	if multiplayer.is_server():
		var world = get_parent()
		if world and world.has_method("register_burning_tree"):
			world.register_burning_tree(self)
