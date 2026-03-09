# Flammable Tree Logic for "Age of Manwe"
#
# This script handles visual state for trees.
# Fire spread logic is now centralized in World.gd for performance.

extends StaticBody3D

@onready var fire_particles = $CPUParticles3D
@onready var fire_light = $FireLight
@export var is_lit: bool = false

func _ready():
	# Configure Collision Layers
	# Layer 2 = Tree/Grass. Mask 0 = Doesn't collide with anything physically.
	collision_layer = 2 
	collision_mask = 0
	
	# Initialize State
	if is_lit:
		fire_particles.emitting = true
		fire_light.visible = true
	else:
		fire_particles.emitting = false
		fire_light.visible = false

# --------------------------------------------------------------------------------------------------
# NETWORKED ACTIONS
# --------------------------------------------------------------------------------------------------

# RPC: Lights this tree on fire on all clients.
@rpc("call_local", "reliable")
func ignite():
	if is_lit: return
	is_lit = true
	fire_particles.emitting = true
	fire_light.visible = true
	
	# Notify the World that we are burning (Server Only)
	if multiplayer.is_server():
		var world = get_parent()
		if world and world.has_method("register_burning_tree"):
			world.register_burning_tree(self)
