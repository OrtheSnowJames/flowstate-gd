extends RefCounted

const Types = preload("res://water/player/types.gd")
const WaterMove = Types.WaterMove


static func _cast_water_move(player, kind: WaterMove, origin: Vector3, aim: Vector3, strength: float) -> void:
	if not player._is_local() or player._ocean == null or player._water_wall_up or Net.arcade.controls(player):
		return
	# resolve once so every peer consumes the same attack
	var hit: Dictionary
	if kind == WaterMove.PELT:
		player._pelt_sequence += 1
		hit = {"id": "%s_%d" % [player.name, player._pelt_sequence]}
	else:
		hit = player._ocean.resolve_wave_hit(origin, aim, strength, player, kind == WaterMove.ATTACK)
	if Net.is_online():
		# call_local so this covers us too no separate local call
		player.rpc("net_cast_water_move", kind, origin, aim, strength, hit)
	else:
		player.net_cast_water_move(kind, origin, aim, strength, hit)


static func net_cast_water_move(player, kind: WaterMove, origin: Vector3, aim: Vector3, strength: float,
		hit: Dictionary = {}) -> void:
	if player._ocean == null or player._water_wall_up:
		return
	# everyone draws the wave only the peer that cast it resolves what it hit
	var apply_hits = player._is_local()
	# the damage range comes from this nodes own stats a lifeguards buffed water_power_damage_max water_attack_damage_max
	match kind:
		WaterMove.POWER, WaterMove.COUNTER:
			if player._ocean.has_method("send_wave"):
				player._ocean.send_wave(origin, aim, strength, player, apply_hits,
						player.water_power_damage_min, player.water_power_damage_max, hit)
			player._play_water_action_anim("water_power")
			if kind == WaterMove.COUNTER:
				player._water_counter_timer = 1.0
				player.net_water_wall(origin + aim * 0.2, aim, 1.0)
		WaterMove.ATTACK:
			if player._ocean.has_method("send_attack_wave"):
				player._ocean.send_attack_wave(origin, aim, strength, player, apply_hits,
						player.water_attack_damage_min, player.water_attack_damage_max, hit)
			player._play_water_action_anim("water_attack")
		WaterMove.PELT:
			player._ocean.send_water_pelt(origin, aim, player, str(hit.get("id", "")))
			player._play_water_action_anim("water_attack")


static func _try_water_counter(player) -> bool:
	if not player._is_local() or player._unconscious or player.movement_locked or player._water_wall_up or Net.is_spectating() \
			or Net.input_blocked_by_menu() or player._ocean == null or player._submersion() <= 0.0 \
			or player.stamina < player.water_counter_stamina_cost:
		return false
	var aim = player._mouse_aim_direction()
	var origin = player.global_position + aim
	origin.y = player._water_height()
	player._cast_water_move(WaterMove.COUNTER, origin, aim, player._water_power_strength())
	player.stamina -= player.water_counter_stamina_cost
	player.momentum = 0.0
	player._water_power_cooldown_timer = player.water_power_cooldown
	return true


static func _update_water_counter(player, delta: float) -> void:
	if player._water_counter_timer <= 0.0:
		return
	player._water_counter_timer = maxf(0.0, player._water_counter_timer - delta)
	if player._water_counter_timer <= 0.0:
		player._cast_water_wall_stop()


static func _try_water_pelt(player) -> bool:
	if not player._is_local() or player._unconscious or player.movement_locked or player._water_wall_up or Net.is_spectating() \
			or Net.input_blocked_by_menu() or player._ocean == null \
			or player.stamina < player.water_pelt_stamina_cost or player._water_pelt_cooldown_timer > 0.0:
		return false
	var origin = player.global_position + Vector3.UP * 0.35
	player._cast_water_move(WaterMove.PELT, origin, player._mouse_aim_direction_3d(origin), 1.0)
	player.stamina -= player.water_pelt_stamina_cost
	player._water_pelt_cooldown_timer = player.water_pelt_cooldown
	return true


static func _cast_water_wall(player, origin: Vector3, aim: Vector3, strength: float) -> void:
	if Net.is_online():
		player.rpc("net_water_wall", origin, aim, strength)
	else:
		player.net_water_wall(origin, aim, strength)


static func net_water_wall(player, origin: Vector3, aim: Vector3, strength: float) -> void:
	player._wall_state = [origin, aim, strength]
	player._water_wall_up = true
	if player._ocean and player._ocean.has_method("start_water_wall"):
		# self keys the wall to this player so two people holding walls at once
		player._ocean.start_water_wall(origin, aim, strength, player)
	player._play_water_wall_anim()


static func _cast_water_wall_stop(player) -> void:
	if Net.is_online():
		player.rpc("net_water_wall_stop")
	else:
		player.net_water_wall_stop()


static func net_water_wall_stop(player) -> void:
	player._water_counter_timer = 0.0
	player._wall_state = []
	player._water_wall_up = false
	if player._ocean and player._ocean.has_method("stop_water_wall"):
		player._ocean.stop_water_wall(player)
	player._stop_water_wall_anim()


static func _water_power_strength(player) -> float:
	var t = clampf(player.momentum / player.max_momentum, 0.0, 1.0)
	return 1.0 + player.water_power_momentum_bonus * pow(t, player.water_power_momentum_exponent)


static func process_input(player, delta: float, submersion: float) -> void:
	if VR.immersive and player._is_local():
		VR.immersion.combat(player, delta)
		return
	if Net.arcade.controls(player):
		return
	# resolve the wall first so simultaneous inputs cannot fire through it
	if Input.is_action_just_pressed("water_counter"):
		player._try_water_counter()
	if player._water_counter_timer <= 0.0 and submersion > 0.0 and Input.is_action_pressed("water_wall") and player.stamina > 0.0 \
			and player._ocean and player._ocean.has_method("start_water_wall"):
		var wall_aim = player._mouse_aim_direction()
		var wall_origin = player.global_position + wall_aim * 1.2
		wall_origin.y = player._water_height()
		player._cast_water_wall(wall_origin, wall_aim, 1.0)
		player._water_wall_up = true
		player.stamina -= player.water_wall_stamina_cost_per_second * delta
	elif player._water_wall_up and player._water_counter_timer <= 0.0:
		player._cast_water_wall_stop()
		player._water_wall_up = false

	# water power press 1 send a wave skimming across the surface toward wherever the
	if not player._water_wall_up and submersion > 0.0 and Input.is_action_just_pressed("water_power") \
			and player.stamina >= player.water_power_stamina_cost \
			and player._water_power_cooldown_timer <= 0.0 \
			and player._ocean and player._ocean.has_method("send_wave"):
		var aim = player._mouse_aim_direction()
		var origin = player.global_position + aim * 1.0
		origin.y = player._water_height()
		# the wave and its animation are raised on every peer from inside the rpc
		player._cast_water_move(WaterMove.POWER, origin, aim, player._water_power_strength())
		player.stamina -= player.water_power_stamina_cost
		player._water_power_cooldown_timer = player.water_power_cooldown
		# spent not banked _water_power_strength already read momentum to compute the strength argument above evaluated
		player.momentum = 0.0

	# water attack water_attack action close range counterpart to water power a much bigger denser
	if not player._water_wall_up and submersion > 0.0 and Input.is_action_just_pressed("water_attack") \
			and player.stamina >= player.water_attack_stamina_cost \
			and player._water_attack_cooldown_timer <= 0.0 \
			and player._ocean and player._ocean.has_method("send_attack_wave"):
		var attack_aim = player._mouse_aim_direction()
		var attack_origin = player.global_position + attack_aim * 0.6
		attack_origin.y = player._water_height()
		player._cast_water_move(WaterMove.ATTACK, attack_origin, attack_aim, 1.0)
		player.stamina -= player.water_attack_stamina_cost
		player._water_attack_cooldown_timer = player.water_attack_cooldown
	if Input.is_action_just_pressed("water_pelt"):
		player._try_water_pelt()
