# Power-up / Item script for "Age of Manwe"
# This script handles items like health packs or speed boosts.
extends Area3D

# enum allows us to create a list of named options for the Editor
enum Type { HEALTH, SPEED }
@export var type: Type = Type.HEALTH
@export var amount = 25.0
@export var duration = 5.0 # How long a speed boost lasts

func _ready():
	# Connect the signal for when something enters the item's pickup zone
	connect("body_entered", _on_body_entered)
	
	# Basic visual animation: make the item spin slowly
	var tween = create_tween().set_loops()
	tween.tween_property(self, "rotation:y", TAU, 2.0).as_relative()

# This is called when a player runs over the item
func _on_body_entered(body):
	# Security: Only the server should process item pickups
	if not multiplayer.is_server(): return

	# Check if the thing that touched us is a Player
	if body.has_method("restore_health") or body.has_method("apply_speed_boost"):
		if type == Type.HEALTH:
			# Give health to the player
			body.restore_health(amount)
		elif type == Type.SPEED:
			# Give a speed boost to the player
			body.apply_speed_boost(1.5, duration) # 50% faster
			
		# The server tells all clients to remove this item
		# queue_free() deletes the node
		queue_free()
