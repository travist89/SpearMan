extends StaticBody3D

@onready var fire_particles = $CPUParticles3D
@export var is_lit = false

func _ready():
	if is_lit:
		fire_particles.emitting = true
	else:
		fire_particles.emitting = false

@rpc("call_local")
func ignite():
	if is_lit: return
	is_lit = true
	fire_particles.emitting = true
