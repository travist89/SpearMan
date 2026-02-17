extends Area3D

@export var type = "health" # or "speed"
@export var amount = 20.0 # Multiplier for speed, value for health
@export var duration = 5.0 # Duration for speed boost

func _ready():
	connect("body_entered", _on_body_entered)
	
	# Simple spin animation using Tween
	var tween = create_tween().set_loops()
	tween.tween_property(self, "rotation:y", deg_to_rad(360), 2.0).as_relative()

func _on_body_entered(body):
	if not multiplayer.is_server(): return

	if body.has_method("restore_health") or body.has_method("apply_speed_boost"):
		if type == "health":
			if body.has_method("restore_health"):
				body.restore_health(amount)
				queue_free()
		elif type == "speed":
			if body.has_method("apply_speed_boost"):
				body.apply_speed_boost(amount, duration)
				queue_free()
