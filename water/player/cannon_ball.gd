extends RefCounted


static func arm(player) -> void:
	var hit: Dictionary = player.Movement._jump_surface(player)
	player._board_jump_available = not hit.is_empty() and hit.collider.is_in_group("diving_board")


static func can_start(player) -> bool:
	return player._board_jump_available and not player._cannon_ball_active and not player._hurdling \
		and not player._unconscious and not player.movement_locked and player._submersion() <= 0.0


static func start(player) -> bool:
	if not can_start(player):
		return false
	player._cannon_ball_active = true
	player._jump_cancel_available = false
	player._water_counter_timer = 0.0
	if player._water_wall_up:
		player._cast_water_wall_stop()
	player._stop_water_wall_anim()
	player._action_anim_lock_movement_state = -1
	player.movement_state = player.MovementState.CANNON_BALL
	player.play_anim(player.AnimationState.CANNON_BALL)
	return true


static func update(player) -> bool:
	if not player._board_jump_available:
		return false
	if player._unconscious or player.movement_locked or Net.is_spectating() or Net.arcade.controls(player):
		reset(player)
		return false
	# only an actual pool entry can deal splash damage
	if is_instance_valid(player._ocean) and player._ocean.overlaps_body(player) and player._submersion() > 0.0:
		var splashing: bool = player._cannon_ball_active
		reset(player)
		if splashing:
			_splash_damage(player)
		return false
	if player.linear_velocity.y <= 0.5 and player.Movement._jump_support(player):
		reset(player)
		return false
	return player._cannon_ball_active


static func _splash_damage(player) -> void:
	if not player._is_local():
		return
	var origin: Vector3 = player.global_position
	origin.y = player._water_height()
	for body in player.get_tree().get_nodes_in_group("player"):
		if body == player or body._unconscious or not player._ocean.overlaps_body(body):
			continue
		if origin.distance_to(body.global_position) > player.cannon_ball_radius:
			continue
		# use the same owner routing and hit credit as water attacks
		player._ocean._apply_hit_damage(body, 1.0, 0.0, 1.0,
			player.cannon_ball_damage, player.cannon_ball_damage, false, player)


static func reset(player) -> void:
	player._board_jump_available = false
	player._cannon_ball_active = false
	if player.movement_state == player.MovementState.CANNON_BALL:
		player.movement_state = player.MovementState.JUMP
