# a physics prop whose simulation lives on the host the host runs it for
extends RigidBody3D


func _ready() -> void:
	if is_multiplayer_authority():
		return

	# freeze_mode_kinematic not static the body still shoves what it runs into as the replicated
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true

	# buoyancy applies force to this body every physics tick on a client thats both
	for child in get_children():
		if child is Buoyancy:
			child.set_physics_process(false)


# knockback from a water move applied on the host where this props physics actually
@rpc("any_peer", "reliable")
func net_apply_impulse(impulse: Vector3) -> void:
	if is_multiplayer_authority():
		apply_central_impulse(impulse)
