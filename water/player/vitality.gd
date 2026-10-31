extends RefCounted

const Types = preload("res://water/player/types.gd")
const MovementState = Types.MovementState


static func _stamina_change(player, delta: float) -> void:
	# bone dry not even wading so theres no water to be tired from recover
	if player._submersion() <= 0.0:
		player.stamina += delta * player.stamina_recovery_out_of_water_per_second
		return

	var _shallow = player.in_shallow_end()
	if _shallow:
		player.stamina += delta * player.stamina_in_shallow_end_per_second
	else:
		if player.movement_state == MovementState.TREAD:
			if player._has_started_moving:
				player.stamina -= delta * player.stamina_expended_in_deep_end_per_second_tread
		elif player.movement_state == MovementState.SWIM:
			player.stamina -= delta * player.stamina_expended_in_deep_end_per_second_swim
		elif player.movement_state == MovementState.GLIDE:
			player.stamina -= delta * player.stamina_expended_in_deep_end_per_second_glide

	if player.stamina <= 5.0:
		player._death()


static func take_stamina_damage(player, amount: float, attacker: int = 0) -> void:
	if player.practice != null and player.practice.infinite_stamina:
		player.stamina = player.max_stamina_per_mode(Net.game_mode)
		return
	if player._water_wall_up:
		amount *= player.water_wall_block_reduction
	if amount > 0.0:
		player._last_damage_peer = attacker
		player._last_damage_time = Time.get_ticks_msec()
	player.stamina = clampf(player.stamina - amount, 0.0, player.max_stamina_per_mode(Net.game_mode))
	if player.stamina <= 5.0:
		player._death()


static func _death(player) -> void:
	if player._unconscious:
		return
	var killer: int = player._last_damage_peer if Time.get_ticks_msec() - player._last_damage_time <= 10000 else 0
	if Net.is_online():
		# call_local so this covers us as well as everyone else
		player.rpc("net_death", killer)
	else:
		player.net_death(killer)


static func net_death(player, killer: int = 0) -> void:
	player.CannonBall.reset(player)
	player.Movement._finish_hurdle(player)
	Net.arcade.ultimate.credit(player, killer)
	if player._unconscious:
		return
	player._unconscious = true
	player._jump_cancel_available = false
	player.movement_state = MovementState.IDLE
	player.momentum = 0.0
	# stop taking input at the source rather than only ignoring it downstream _input stops
	player.set_process_input(false)

	# that may have been the last one standing on this side told rather than
	if player.practice == null:
		Net.call_deferred("on_player_down")

	# a wall left standing when its owner blacks out would hang in the pool
	if player._water_wall_up:
		player.net_water_wall_stop()
	# clear the walls animation hold too whether or not a wall was up it
	player._stop_water_wall_anim()

	# dropping played on every peer not just the dying one watching somebody go under
	if player._anim_player and player._anim_player.has_animation("death"):
		player._anim_player.play("death")
		player._movement_anim_state = -1 # same reasoning as _play_water_action_anim

	# past here is what blacking out looks like from behind your own eyes the
	if player.practice != null or not player._is_local():
		return

	if player._muffled_player:
		player._muffled_player.play()

	player._eyelid_tween = player.create_tween()
	if player._eyelid and player._eyelid.material:
		# 0 0 is a wide open eye 1 0 fully shut see eye_closing gdshader
		player._eyelid.material.set_shader_parameter("progress", 0.0)
		# half the ear ringing clip so the lids finish falling while the ring is
		var _duration = player.blackout_time
		if player._muffled_player and player._muffled_player.stream:
			_duration = player._muffled_player.stream.get_length() / 2
		# linear on purpose progress isnt one animation any more its the clock the shader
		player._eyelid_tween.set_trans(Tween.TRANS_LINEAR)
		player._eyelid_tween.tween_method(
			func(val: float) -> void:
				var curved = 1.0 - pow(1.0 - val, 5.0)
				player._eyelid.material.set_shader_parameter("progress", curved),
			0.0,
			1.0,
			_duration)
	else:
		player._eyelid_tween.tween_interval(player.blackout_time)
	# hand off after the final eyelid update so it cannot cover the spectator view
	player._eyelid_tween.tween_callback(func() -> void:
		if player._unconscious and player.is_inside_tree():
			Net.enter_spectator_after_faint())


static func revive(player) -> void:
	if not player._unconscious:
		return
	if Net.is_online():
		# call_local so this covers us as well as everyone else
		player.rpc("net_revive")
	else:
		player.net_revive()


static func net_revive(player) -> void:
	if not player._unconscious:
		return
	player._unconscious = false
	player._last_damage_peer = 0
	player._last_damage_time = 0
	Net.arcade.ultimate.reset_life(player)
	player._jump_cancel_available = false
	player.set_process_input(true)
	player.stamina = player.max_stamina_per_mode(Net.game_mode) * player.revive_stamina_fraction
	player.momentum = 0.0
	player.movement_state = MovementState.TREAD
	# the death clip holds on its last frame and _anim_change refuses to touch the
	player._movement_anim_state = -1
	# a double tap registered before blacking out shouldnt cash in as a dodge the
	player.last_a_press = -1000.0
	player.last_d_press = -1000.0

	# past here is what coming round looks like from behind your own eyes the
	if player.practice != null or not player._is_local():
		return

	if player._muffled_player:
		player._muffled_player.stop()

	Net.exit_spectator_mode()
	if player.take_over_camera:
		player._camera.current = true

	player.shake_camera(player.revive_shake_strength, player.revive_shake_time)

	# cancel the close and its spectator handoff
	if player._eyelid_tween and player._eyelid_tween.is_valid():
		player._eyelid_tween.kill()
	if player._eyelid and player._eyelid.material:
		# snap open from wherever the lids actually are not from a fixed value so
		var from: float = player._eyelid.material.get_shader_parameter("progress")
		player._eyelid_tween = player.create_tween()
		player._eyelid_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		player._eyelid_tween.tween_method(
			func(val: float) -> void:
				player._eyelid.material.set_shader_parameter("progress", val),
			from,
			0.0,
			player.eyelid_open_time)


static func respawn(player, at: Vector3, yaw: float) -> void:
	player.CannonBall.reset(player)
	player.Movement._finish_hurdle(player)
	player.net_revive()
	player._jump_cancel_available = false
	player.global_position = at
	player.rotation = Vector3(0, yaw, 0)
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player._remote_transform = player.transform
	player._remote_from = player.transform
	player._remote_blend = 1.0
	player.reset_physics_interpolation()
	player.stamina = player.max_stamina_per_mode(Net.game_mode)
	player.momentum = 0.0


static func _revive_target(player) -> Node:
	if not player.is_lifeguard or player._unconscious:
		return null
	var best: Node = null
	var best_dist = player.revive_range
	for other in player.get_tree().get_nodes_in_group("player"):
		if other == player or not is_instance_valid(other):
			continue
		# duck typed matching how the rest of this file talks to other bodies anything
		if not ("_unconscious" in other and "team" in other):
			continue
		if not other._unconscious or other.team != player.team:
			continue
		var dist = player.global_position.distance_to(other.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = other
	return best


static func _try_revive_nearby(player) -> void:
	var target = player._revive_target()
	if target:
		target.revive()
