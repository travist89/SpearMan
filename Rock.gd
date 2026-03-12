# Rock Projectile Logic for "Age of Manwe"
extends RigidBody3D

@export var damage: float = 15.0
@export var impact_force: float = 10.0

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	connect("body_entered", _on_body_entered)
	
	if has_meta("initial_velocity"):
		linear_velocity = get_meta("initial_velocity")
	
	if multiplayer.is_server():
		await get_tree().create_timer(10.0).timeout
		if is_instance_valid(self):
			queue_free()

func _on_body_entered(body):
	if not multiplayer.is_server(): return

	if body.has_method("take_damage"):
		if body.name.is_valid_int():
			body.take_damage.rpc(damage)
		else:
			body.take_damage(damage)
		
		if body is CharacterBody3D:
			var direction = -global_transform.basis.z.normalized()
			body.velocity += direction * impact_force
			
		queue_free() 
		return
	
	if body.has_method("explode"):
		body.explode.rpc()
		queue_free()
		return
