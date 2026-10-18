extends RefCounted

const Types = preload("res://water/player/types.gd")
const MovementState = Types.MovementState


static func _integrate_forces(player, state: PhysicsDirectBodyState3D) -> void:
	if not player._is_local() or not Net.is_online() or player.multiplayer.is_server() or player._unconscious or player.movement_locked:
		return
	for i in range(state.get_contact_count()):
		var body = state.get_contact_collider_object(i)
		if is_instance_valid(body) and body.has_method("queue_contact_push"):
			var impulse = state.get_contact_impulse(i)
			if impulse.dot(body.global_position - player.global_position) < 0.0:
				impulse = -impulse
			body.queue_contact_push(impulse)


static func detect_dodge(player, now: float, event: InputEvent) -> void:
	if event.is_action_pressed("forward") \
		or event.is_action_pressed("back") \
		or event.is_action_pressed("swim_key"):
		return
	if event.is_action_pressed("left"):
		if now - player.last_a_press <= player.DODGE_DOUBLE_TAP_TIME:
			player._dodge_left()

		player.last_a_press = now

	if event.is_action_pressed("right"):
		if now - player.last_d_press <= player.DODGE_DOUBLE_TAP_TIME:
			player._dodge_right()

		player.last_d_press = now


static func _dodge_left(player) -> void:
	if player.ANIMATE_PLAYER:
		player._anim_player.play("dodge_left")
		player._movement_anim_state = -1 # same reasoning as _play_water_action_anim
	player._dodge(Vector3.LEFT)


static func _dodge_right(player) -> void:
	if player.ANIMATE_PLAYER:
		player._anim_player.play("dodge_right")
		player._movement_anim_state = -1
	player._dodge(Vector3.RIGHT)


static func _dodge(player, local_dir: Vector3) -> void:
	if player.DEBUG_IN_SHALLOW_WATER:
		print("dodge attempt: shallow=", player.in_shallow_end(), " submersion=", player._submersion(),
				" stamina=", player.stamina, "/", player.stamina_expended_dodge,
				" cooldown=", player._dodge_cooldown_timer,
				" wants_swim=", Input.is_action_pressed("swim_key"))
	if not player.in_shallow_end() or player.stamina < player.stamina_expended_dodge or player._dodge_cooldown_timer > 0.0:
		return
	player.stamina -= player.stamina_expended_dodge
	player._dodge_cooldown_timer = player.dodge_cooldown

	# 1 momentum and direction clamped to momentum_needed_to_swim too not just dodge_momentum a dodge is
	player.dir = (player.transform.basis * local_dir).normalized()
	player.momentum = max(player.momentum, player.dodge_momentum, player.momentum_needed_to_swim)

	# 2 impulse
	var right = player._camera.global_basis.x
	if local_dir == Vector3.LEFT:
		right = -right
	player.apply_central_impulse(right * player.dodge_impulse)


static func _jump(player, on_ground: bool) -> void:
	if player._jump_cooldown_timer > 0.0:
		return
	var cube_boost = player._can_cube_jump()
	if not cube_boost and (not on_ground or player.momentum <= 0.0):
		return
	player._jump_cooldown_timer = player.jump_cooldown
	# diminishing returns on momentum the exponent 1 flattens the curve so arriving at full
	var t = clampf(player.momentum / player.max_momentum, 0.0, 1.0)
	player.linear_velocity.y = player.cube_jump_speed if cube_boost else player.jump_speed * pow(t, player.jump_momentum_exponent)
	player._jump_cancel_available = player._submersion() > 0.0
	player.momentum = 0.0
	player.movement_state = MovementState.JUMP


static func _try_jump_cancel(player) -> bool:
	if not player._is_local() or not player._jump_cancel_available:
		return false
	if player._unconscious or player.movement_locked or Net.input_blocked_by_menu() or Net.is_spectating() \
			or player._submersion() <= 0.0 or player.linear_velocity.y <= 0.0:
		player._jump_cancel_available = false
		return false
	if player.stamina < player.jump_cancel_stamina_cost:
		return false
	player._jump_cancel_available = false
	player.stamina -= player.jump_cancel_stamina_cost
	player.momentum = minf(player.momentum + player.jump_cancel_momentum, player.max_momentum)
	# turn the rising jump into a horizontal burst
	var horizontal = Vector3(player.linear_velocity.x, 0.0, player.linear_velocity.z)
	var axis = Input.get_axis("forward", "back")
	var direction = player.global_basis * Vector3(0.0, 0.0, axis)
	if direction.is_zero_approx():
		direction = horizontal if horizontal.length() > 0.1 else -player.global_basis.z
	direction.y = 0.0
	player.dir = direction.normalized()
	player.linear_velocity = player.dir * maxf(horizontal.length(), player.swim_speed * player.momentum / player.max_momentum)
	player.movement_state = MovementState.SWIM
	player.can_move = true
	return true


static func _can_cube_jump(player) -> bool:
	var scene = player.get_tree().current_scene
	var cube = scene.get_node_or_null("PushCube") as Node3D if scene else null
	if cube == null or cube.is_queued_for_deletion():
		return false
	var offset = player.global_position - cube.global_position
	if Vector2(offset.x, offset.z).length() > player.cube_jump_range or absf(offset.y) > player.cube_jump_range:
		return false
	if player._submersion() > 0.0:
		return true
	# dry jumps need support so hovering near the cube cannot grant another boost
	var query = PhysicsRayQueryParameters3D.create(
		player.global_position, player.global_position + Vector3.DOWN * (player.body_half_height + 0.2))
	query.exclude = [player.get_rid()]
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


static func _turn_from_input(player, delta: float) -> void:
	var turn = Input.get_axis("left", "right")
	if turn == 0.0:
		player._turn_hold_time = 0.0
		return

	var rate = player.turn_speed
	if player.exponential_turn_sensitivity:
		# same exponential approach idiom as camera_turn_speed camera_pitch_speed above 1 0 exp t tau ramps
		player._turn_hold_time += delta
		rate *= 1.0 - exp(-player._turn_hold_time / player.turn_ramp_time)
	else:
		player._turn_hold_time = 0.0

	player.rotate_y(-turn * rate * delta)


static func _drift_to_a_stop(player) -> void:
	player._jump_cancel_available = false
	var v = player.linear_velocity
	player.apply_central_force(
		Vector3(-v.x, 0.0, -v.z) * (player.water_linear_drag * 1.5) * player.mass)
	player._apply_buoyancy(player._submersion())


static func _submersion(player) -> float:
	var bottom = player.global_position.y - player.body_half_height
	return clampf((player._water_height() - bottom) / (2.0 * player.body_half_height), 0.0, 1.0)


static func in_shallow_end(player) -> bool:
	var water_y = player._water_height()
	# not in the water at all nothing to be shallow in
	if water_y <= player.global_position.y - player.body_half_height:
		return false
	var space = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player.global_position, player.global_position + Vector3.DOWN * player.ground_probe)
	query.exclude = [player.get_rid()]
	var result = space.intersect_ray(query)
	if result.is_empty():
		return false
	var collider = result.get("collider")
	if not (collider is Node):
		return false
	if not ((player._shallow_floor and (collider == player._shallow_floor or player._shallow_floor.is_ancestor_of(collider))) \
			or (player._transition_floor and (collider == player._transition_floor or player._transition_floor.is_ancestor_of(collider)))):
		return false
	# which mesh is underfoot isnt enough on its own transition is one long ramp
	return water_y - result.position.y <= 2.0 * player.body_half_height


static func _swim_up_animation_time(player) -> float:
	if player.momentum >= player.momentum_needed_to_swim:
		return 0.0

	var t = player.momentum / player.momentum_needed_to_swim
	return lerp(0.5, 1.5, t)


static func _swim_up_time_remaining(player) -> float:
	if player.momentum_needed_to_swim <= 0.0:
		return 0.0
	var k = player._swim_gain_scale * player.momentum_gain_mult
	if k <= 0.0:
		return 0.0
	var u = clampf(player.momentum / player.momentum_needed_to_swim, 0.0, 1.0)
	return (1.0 - u * 0.5 - u * u * 0.5) / k


static func _water_height(player) -> float:
	if player._ocean:
		if player._ocean.has_method("get_rest_height"):
			return player._ocean.get_rest_height()
		if player._ocean.has_method("get_height_at"):
			return player._ocean.get_height_at(player.global_position)
	return 0.0


static func _walk(player, delta: float) -> void:
	player.can_move = true
	# forward back only left right now turn instead of strafing see _turn_from_input same as
	var input_dir = Vector2(0.0, Input.get_axis("forward", "back"))
	var direction = (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# walk while moving idle when standing still
	player.movement_state = MovementState.WALK if direction else MovementState.IDLE

	# momentum is the only speed modifier so walking wading builds momentum too but only
	if direction:
		player.momentum = move_toward(player.momentum, player.max_momentum_by_walking, player.SWIM_GAIN * delta)
	else:
		player.momentum = move_toward(player.momentum, 0.0, player.SWIM_GAIN * delta)

	# speed comes from momentum via the shared drag thrust so wading has the same
	player._apply_swim_motion(direction, player.momentum / player.max_momentum)


static func _swim(player, delta: float) -> void:
	var in_shallow = player.in_shallow_end()
	if player.DEBUG_IN_SHALLOW_WATER:
		print("in_shallow: ", in_shallow)
	if not Input.is_action_pressed("swim_key"):
		player._glide(delta)
		return
	# actively swimming re enables movement after a tread stopped it so the player isnt
	player.can_move = true
	# momentum 0 0 1 0
	var t = player.momentum / player.max_momentum

	# intentional swim thrust direction horizontal only forward back only left right turn instead of
	var input_dir = Vector2(0.0, Input.get_axis("forward", "back"))
	if Input.is_action_pressed("back"):
		player._last_backstroke_time = player._time_since_start()
	# switch a backstroke s straight into a forward stroke w without releasing the swim
	if (Input.is_action_just_pressed("forward")
			and player._time_since_start() - player._last_backstroke_time <= player.BACKSTROKE_FLIP_WINDOW):
		player.rotate_y(PI)

	# horizontal only off the bodys own facing same as _walk not the cameras the
	player.dir = (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y))

	# with enough momentum already banked a stroke should just move instantly not ease in
	if player.momentum >= player.momentum_needed_to_swim and player.dir.length() > 0.01:
		var speed = Vector2(player.linear_velocity.x, player.linear_velocity.z).length()
		var redirected = player.dir.normalized() * speed
		player.linear_velocity.x = redirected.x
		player.linear_velocity.z = redirected.z

	# the wake ripples and bow wave come purely from the fluid sim reacting to

	# build momentum only while actually pushing forward back holding swim_key alone with no w
	if input_dir.y != 0.0:
		# during the swim up wind up pace it so momentum reaches the swim threshold
		var gain_scale = player.forward_swim_gain_mult if input_dir.y < 0.0 else 1.0
		# cached for _swim_up_time_remaining so the wind up animation is paced off the same stroke
		player._swim_gain_scale = gain_scale
		var swim_up_time = player._swim_up_animation_time()
		if swim_up_time > 0.0:
			player.momentum += player.momentum_needed_to_swim / swim_up_time * delta * gain_scale * player.momentum_gain_mult
		else:
			player.momentum += player.SWIM_GAIN * pow(1.0 - t, 2.0) * delta * gain_scale * player.momentum_gain_mult
		player.momentum = min(player.momentum, player.max_momentum)
	else:
		# deep water idle decay momentum_loss_mult is the kickboards lose less in the deep end
		player.momentum = move_toward(player.momentum, 0.0, player.SWIM_GAIN * delta * player.momentum_loss_mult)

	# swim_up is the wind up phase spent building the momentum needed to swim see
	player.movement_state = MovementState.SWIM if player.momentum >= player.momentum_needed_to_swim else MovementState.SWIM_UP

	# drag thrust shared with gliding so both top out at the same speed
	player._apply_swim_motion(player.dir, t)


static func _glide(player, delta: float) -> void:
	# go along path conserving momentum but not gaining any basically like swimming but lose
	var glide_dir = Vector3(player.dir.x, 0.0, player.dir.z)

	# press a movement key to cancel the glide or stop dead if we hit
	if (Input.is_action_just_pressed("forward")
			or Input.is_action_just_pressed("back")
			or player._wall_ahead(glide_dir)):
		player._stop_gliding()
		return

	if player.momentum > 0.0:
		player.movement_state = MovementState.GLIDE
		# momentum_loss_mult the other deep water spot the kickboards lose less applies alongside _swim s
		player.momentum -= player.SWIM_GAIN * delta * player.momentum_loss_mult
		var t = player.momentum / player.max_momentum
		player._apply_swim_motion(glide_dir, t)
	else:
		player.momentum = 0.0
		player._tread()


static func _apply_water_drag(player, t: float) -> void:
	var v = player.linear_velocity
	var drag: float = lerp(player.water_linear_drag * 1.5, player.water_linear_drag * 0.5, t)
	player._apply_central_force(Vector3(-v.x, 0.0, -v.z) * drag * player.mass)


static func _apply_swim_motion(player, move_dir: Vector3, t: float) -> void:
	player._apply_water_drag(t)
	if move_dir.length() > 0.01:
		var swim_force: float = lerp(player.swim_speed * 0.5, player.swim_speed * 1.5, t)
		player._apply_central_force(move_dir.normalized() * swim_force * player.mass)


static func _wall_ahead(player, direction: Vector3) -> bool:
	if direction.length() < 0.01:
		return false
	var space = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player.global_position, player.global_position + direction.normalized() * player.wall_probe)
	query.exclude = [player.get_rid()]
	var result = space.intersect_ray(query)
	if result.is_empty():
		return false
	var normal: Vector3 = result.normal
	return absf(normal.y) < 0.5


static func _stop_gliding(player) -> void:
	player.linear_velocity.x = 0.0
	player.linear_velocity.z = 0.0
	player._tread()


static func _tread(player) -> void:
	player.movement_state = MovementState.TREAD
	# reset momentum
	player.momentum = 0.0
	# stop movement
	player.can_move = false


static func _apply_buoyancy(player, submersion: float) -> void:
	var v = player.linear_velocity
	# lift submersion target g at the target depth this equals gravity which the engine
	var lift_accel = submersion / player.target_submersion * player._gravity
	# auto critical damping the springs stiffness is k g 2h target so a damping
	var k = player._gravity / (2.0 * player.body_half_height * player.target_submersion)
	var damping = 2.0 * player.damping_ratio * sqrt(k)
	# damping scales with submersion alongside the lift so out of the water this whole
	var accel = lift_accel - v.y * damping * submersion
	# buoyancy is passive physics apply it directly never gated by can_move or the player
	player.apply_central_force(Vector3.UP * accel * player.mass)


static func _apply_central_force(player, force: Vector3) -> void:
	if player.can_move:
		player.apply_central_force(force)


static func update(player, delta: float, submersion: float, shallow: bool) -> void:
	if submersion <= 0.0 or player.linear_velocity.y <= 0.0:
		player._jump_cancel_available = false

	if Input.is_action_just_pressed("jump"):
		# cube boosts can also launch from the water
		player._jump(shallow or submersion <= 0.0)
	if Input.is_action_just_pressed("swim_key"):
		player._try_jump_cancel()

	# entry exit splashes are handled by the water sim itself it detects the body

	# movement mode you can swim wherever theres enough water by holding the swim key
	var wants_swim = Input.is_action_pressed("swim_key")

	if wants_swim and (shallow or submersion > 0.25):
		player._swim(delta)
	elif shallow:
		player._walk(delta) # shallow end always walks unless actively swimming
	elif submersion > 0.25:
		player._swim(delta) # not holding swim in open water glides
	else:
		player._walk(delta)

	# gravity stays on everywhere buoyancy grows smoothly with submersion so the body has one
	if not (shallow and not wants_swim):
		player._apply_buoyancy(submersion)

	# baseline momentum for wading in the shallows
	if shallow:
		player.momentum = max(player.momentum_in_shallow_end, player.momentum)
