# LightningBolt Logic for "Age of Manwe"
#
# This script handles the visual effect of a lightning strike in the world.
# It uses a Tween to rapidly scale up and increase light energy, then fade out.
# Network Architecture: This scene is purely visual and is instantiated locally 
# on all clients via an RPC call from the server (World.gd).

extends Node3D

@onready var mesh_instance = $MeshInstance3D
@onready var omni_light = $OmniLight3D

func _ready():
	# Start invisible/small
	scale = Vector3(0.1, 1.0, 0.1)
	mesh_instance.transparency = 0.0
	
	# Animate the lightning strike
	var tween = create_tween()
	
	# Flash in
	tween.tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.05).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(omni_light, "light_energy", 50.0, 0.05) # Increased brightness (was 10.0)
	
	# Fade out
	tween.tween_property(mesh_instance, "transparency", 1.0, 0.2).set_delay(0.1)
	tween.parallel().tween_property(omni_light, "light_energy", 0.0, 0.2).set_delay(0.1)
	
	# Delete after animation
	tween.tween_callback(queue_free)
