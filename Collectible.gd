# Collectible Item Logic for "Age of Manwe"
extends Area3D

enum Type { HEALTH, SPEED }
@export var type: Type = Type.HEALTH
@export var amount: float = 25.0       
@export var duration: float = 5.0      

func _ready():
	connect("body_entered", _on_body_entered)
	
	var tween = create_tween().set_loops()
	tween.tween_property(self, "rotation:y", TAU, 2.0).as_relative()

func _on_body_entered(body):
	if not multiplayer.is_server(): return

	if body.has_method("restore_health") or body.has_method("apply_speed_boost"):
		if type == Type.HEALTH:
			body.restore_health.rpc(amount)
			
		elif type == Type.SPEED:
			body.apply_speed_boost.rpc(1.5, duration) 
			
		queue_free()
