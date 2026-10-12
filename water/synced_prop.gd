# a physics prop whose simulation lives on the host the host runs it for
extends RigidBody3D

var _pending_push := Vector3.ZERO
var _push_timer := 0.0
var _last_push: Dictionary = {}


func queue_contact_push(impulse: Vector3) -> void:
	if impulse.is_finite() and not is_multiplayer_authority():
		_pending_push += impulse


func _physics_process(delta: float) -> void:
	if not Net.is_online() or is_multiplayer_authority():
		return
	_push_timer += delta
	if _push_timer < 0.05:
		return
	_push_timer = 0.0
	if not _pending_push.is_zero_approx():
		rpc_id(get_multiplayer_authority(), "net_contact_push", _pending_push.limit_length(30.0))
		_pending_push = Vector3.ZERO


@rpc("any_peer", "unreliable")
func net_contact_push(impulse: Vector3) -> void:
	if not is_multiplayer_authority() or not impulse.is_finite() or Net._round_over or Net.round_state != Net.RoundState.PLAYING:
		return
	var sender := multiplayer.get_remote_sender_id()
	var players := Net._players_root()
	var player := players.get_node_or_null(str(sender)) if players else null
	if player == null or player._unconscious or player.movement_locked:
		return
	if player.global_position.distance_to(global_position) > 3.5:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_push.get(sender, -1000)) < 40:
		return
	_last_push[sender] = now
	# client contacts push the host body without simulating a second cube
	apply_central_impulse(impulse.limit_length(30.0))


func _ready() -> void:
	if is_multiplayer_authority():
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		reset_physics_interpolation()
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
