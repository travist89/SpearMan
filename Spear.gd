# Spear Projectile for "Age of Manwe"
extends RigidBody3D

@export var damage = 10
@export var stick_probability = 0.8
@export var is_fire_spear = false

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	connect("body_shape_entered", _on_body_shape_entered)
	connect("body_entered", _on_body_entered)
	
	if has_meta("initial_velocity"):
		linear_velocity = get_meta("initial_velocity")

func _on_body_shape_entered(body_rid, body, body_shape_index, local_shape_index):
	if not multiplayer.is_server(): return
	
	if body is CharacterBody3D and body.has_method("take_damage") and not body.name.is_valid_int():
		var owner_id = body.shape_find_owner(body_shape_index)
		var shape_node = body.shape_owner_get_owner(owner_id)
		
		if shape_node:
			body.take_damage(damage)
			stick_to_target.rpc(shape_node.get_path())
			return

func _on_body_entered(body):
	if freeze: return
	if not multiplayer.is_server(): return

	if body.has_method("take_damage"):
		if not body.name.is_valid_int():
			body.take_damage(damage)
			stick_to_target.rpc(body.get_path())
			return

	if is_fire_spear and body.has_method("ignite"):
		body.ignite.rpc()

	if body.has_method("explode"):
		if has_meta("owner_id"):
			var owner_id = get_meta("owner_id")
			if body.name.begins_with("Target"):
				body.explode.rpc(owner_id)
			else:
				body.explode.rpc()
		else:
			body.explode.rpc()
		queue_free()
		return

	if body is StaticBody3D or body is CSGShape3D:
		stick_to_target.rpc(body.get_path())

@rpc("authority", "call_local", "reliable")
func stick_to_target(target_path):
	var target = get_node_or_null(target_path)
	if target:
		# We must defer physics/scene tree changes because this might be called during a physics step
		_perform_stick.call_deferred(target)

func _perform_stick(target):
	if not is_inside_tree(): return
	
	freeze = true
	$CollisionShape3D.disabled = true
	
	if target is StaticBody3D or target is CSGShape3D:
		return

	# We use a RemoteTransform3D to stick to moving targets (like Enemies).
	# See GODOT_NETWORKING_DOCS.md "Sticking Projectiles" for why reparent() is not used.
	var pivot = Node3D.new()
	target.add_child(pivot)
	pivot.global_transform = global_transform
	
	var remote = RemoteTransform3D.new()
	pivot.add_child(remote)
	remote.remote_path = get_path()
	remote.update_position = true
	remote.update_rotation = true
	remote.update_scale = false
