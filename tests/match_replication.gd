# run a host two players and a late spectator with the matching test argument
extends Node

var role := ""
var roles: Dictionary = {}
var checks: Dictionary = {}
var failed := false
var test_port := int(OS.get_environment("FLOWSTATE_TEST_PORT")) if OS.has_environment("FLOWSTATE_TEST_PORT") else 17654


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			role = arg.trim_prefix("--test=")
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(60.0).timeout.connect(func() -> void: _fail("test timed out"))
	if role == "host":
		await _host()
	else:
		Net._connect_flow_active = true
		if Net.join_game("127.0.0.1", test_port) != OK:
			_fail("could not connect")
			return
		await multiplayer.connected_to_server
		rpc_id(1, "register_role", role)
		if role == "spectator":
			await _until(func() -> bool: return Net._connection_game_in_progress)
			get_tree().node_added.connect(_pause_spectator_camera)
			call_deferred("_choose_spectate")
			await Net._show_game_in_progress_prompt()
			await _until(func() -> bool: return _players().size() == 3)
			await _check_join()
			get_tree().node_added.disconnect(_pause_spectator_camera)
			Net._spectator_camera.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			await _until(func() -> bool: return _players().size() == 3)
			var local := _body(multiplayer.get_unique_id())
			local.freeze = true
			local.set_physics_process(false)


func _host() -> void:
	if Net.host_game(test_port) != OK:
		_fail("could not host")
		return
	await _until(func() -> bool: return roles.has("first") and roles.has("second"))
	Net._teams = {1: 0, roles.first: 1, roles.second: 0}
	Net._broadcast_roster()
	Net.start_round()
	await _until(func() -> bool: return _players().size() == 3)
	await _until(func() -> bool: return not _body(1).movement_locked)
	Net._lifeguards = {0: 1, 1: roles.first}
	Net._broadcast_roster()
	var host := _body(1)
	host.freeze = true
	host.set_physics_process(false)
	host.position = Vector3(-20, 6, -5)
	var prop := get_tree().current_scene.get_node("PushCube")
	prop.freeze = true
	prop.position = Vector3(15, 8, 7)
	host._cast_water_wall(Vector3(-20, 4, -6), Vector3.FORWARD, 1.0)
	rpc_id(roles.second, "change_faint", true)
	await _until(func() -> bool: return _body(roles.second)._unconscious)
	_expect(Net._spectator_drones.is_empty(), "no drone before a spectator joins")
	print("READY_FOR_SPECTATOR")
	await _until(func() -> bool: return roles.has("spectator") and Net._spectator_targets.get(roles.spectator, 0) == 1)
	var watching_drone: Node3D = Net._spectator_drones[1]
	_expect(watching_drone.visible, "players see the spectator drone")
	_expect(watching_drone.global_position.y > host.global_position.y + 20.0, "drone arrives from the sky")
	await get_tree().create_timer(0.7).timeout
	_expect(watching_drone.global_position.distance_to(host.global_position + Vector3.UP * 4.5) < 0.2, "fast drone descent")
	await _until(func() -> bool: return checks.has("join"))
	print("PASS game in progress drone launch")
	rpc_id(roles.second, "watch_after_faint")
	await _until(func() -> bool: return Net._spectator_targets.get(roles.second, 0) == 1)
	_expect(Net._spectator_targets.size() == 2, "both spectators registered")
	_expect(Net._spectator_drones.size() == 1 and Net._spectator_drones[1] == watching_drone, "spectators share one drone")
	rpc_id(roles.first, "check_player_drone", 1)
	await _until(func() -> bool: return checks.has("player drone"))
	host._cast_water_wall_stop()
	host.position = Vector3(-12, 6, -5)
	host.rotation.y = 0.8
	prop.position = Vector3(18, 8, 7)
	host._play_water_action_anim("dodge_left")
	rpc_id(roles.first, "move_player", Vector3(10, 6, 4))
	rpc_id(roles.second, "change_faint", false)
	await get_tree().create_timer(0.4).timeout
	rpc_id(roles.spectator, "check_live", roles.first, roles.second)
	await _until(func() -> bool: return checks.has("live"))
	_expect(Net._spectator_targets.size() == 1, "reviving removes that spectator")
	_expect(not watching_drone.departing, "remaining spectator keeps the drone")
	_expect(watching_drone.global_position.distance_to(host.global_position + Vector3.UP * 4.5) < 0.3, "drone tracks the lifeguard")
	host._cast_water_move(host.WaterMove.POWER, Vector3(-20, 4, 0), Vector3.RIGHT, 4.0)
	await get_tree().create_timer(0.1).timeout
	rpc_id(roles.spectator, "check_wave")
	await _until(func() -> bool: return checks.has("wave"))
	host._death()
	await get_tree().create_timer(0.3).timeout
	rpc_id(roles.spectator, "check_score", roles.first)
	await _until(func() -> bool: return checks.has("score"))
	_expect(watching_drone.departing, "old drone leaves when the target faints")
	_expect(Net._spectator_targets.get(roles.spectator, 0) == roles.first, "spectator drone changes lifeguards")
	# keep the round open so both lifeguards can faint and trigger drone view
	Net._round_over = true
	rpc_id(roles.first, "change_faint", true)
	await get_tree().create_timer(0.4).timeout
	rpc_id(roles.spectator, "check_drone")
	await _until(func() -> bool: return checks.has("drone"))
	Net._round_over = false
	Net.on_player_down()
	await _until(func() -> bool: return Net.round_state == Net.RoundState.LOBBY)
	await get_tree().create_timer(1.0).timeout
	Net.start_round()
	await _until(func() -> bool: return _players().size() == 3)
	await _until(func() -> bool: return not _body(1).movement_locked)
	rpc_id(roles.spectator, "check_next_round")
	await _until(func() -> bool: return checks.has("next round"))
	await _until(func() -> bool: return Net._spectator_targets.has(roles.spectator))
	await get_tree().create_timer(0.7).timeout
	var watched_id: int = Net._spectator_targets[roles.spectator]
	var departing_drone: Node3D = Net._spectator_drones[watched_id]
	var departure_height := departing_drone.global_position.y
	rpc_id(roles.spectator, "leave_spectating")
	await _until(func() -> bool: return not Net._spectator_targets.has(roles.spectator))
	await get_tree().create_timer(0.1).timeout
	_expect(departing_drone.departing and departing_drone.global_position.y > departure_height, "disconnect sends the drone back up")
	await get_tree().create_timer(0.7).timeout
	_expect(not is_instance_valid(departing_drone), "departed drone is removed")
	print("PASS spectator drone lifecycle")
	rpc("finish")
	finish()


func _check_join() -> void:
	var fainted := 0
	for player in _players():
		if player._unconscious:
			fainted += 1
	var host := _body(1)
	_expect(host.position.distance_to(Vector3(-20, 6, -5)) < 0.1, "late host position")
	_expect(host.is_lifeguard, "late lifeguard role")
	_expect(fainted == 1, "late fainted state")
	_expect(host._wall_anim_active, "late wall animation")
	_expect(get_tree().current_scene.get_node("water base")._walls.size() == 1, "late wall")
	_expect(Net._round_blue_score == 1, "late scoreboard score")
	_expect(Net._round_blue_goal == 2 and Net._round_red_goal == 1, "late scoreboard goals")
	var board := get_tree().current_scene.get_node("Scoreboard")
	_expect(board.blue_score.text == "1" and board.blue_goal.text == "Goal: 2 points", "late scoreboard labels")
	_expect(get_tree().current_scene.get_node("PushCube").position.distance_to(Vector3(15, 8, 7)) < 0.1, "late prop position")
	_expect(Net._spectator_camera._living_lifeguard() == host, "lifeguard camera target")
	_expect(_body(multiplayer.get_unique_id()) == null, "spectator has no player body")
	_expect(not get_tree().current_scene.get_node("water base").get_active_waves().is_empty(), "late active wave")
	_expect(Net._spectator_drones.has(1), "late spectator receives existing drones")
	_expect(not Net._spectator_drones[1].visible, "drones are hidden from spectators")
	_expect(Net._spectator_drones[1].find_children("*", "Camera3D", true, false).is_empty(), "model camera removed")
	rpc_id(1, "checked", "join")


func _pause_spectator_camera(node: Node) -> void:
	if node.name == "SpectatorCamera":
		# joining must launch the drone before the camera starts reporting targets
		node.process_mode = Node.PROCESS_MODE_DISABLED


func _choose_spectate() -> void:
	await _until(func() -> bool: return Transition.has_node("DisconnectPrompt"))
	var prompt := Transition.get_node("DisconnectPrompt")
	await _until(func() -> bool: return prompt._open)
	_expect(prompt._message.text == "Game in progress...", "game in progress prompt")
	prompt._choose(true)


@rpc("any_peer", "reliable")
func register_role(value: String) -> void:
	roles[value] = multiplayer.get_remote_sender_id()
	if value == "spectator":
		var host := _body(1)
		host._cast_water_move(host.WaterMove.POWER, Vector3(-20, 4, 0), Vector3.RIGHT, 4.0)
		host._cast_water_wall(Vector3(-20, 4, -6), Vector3.FORWARD, 1.0)


@rpc("authority", "reliable")
func move_player(pos: Vector3) -> void:
	_body(multiplayer.get_unique_id()).position = pos


@rpc("authority", "reliable")
func change_faint(down: bool) -> void:
	var local := _body(multiplayer.get_unique_id())
	if down:
		if role == "second":
			# delay faint spectating until the late join is checked
			local.blackout_time = 30.0
			local._muffled_player = null
		local._death()
	else:
		local.revive()


@rpc("authority", "reliable")
func watch_after_faint() -> void:
	Net.enter_spectator_after_faint()


@rpc("authority", "reliable")
func check_player_drone(target: int) -> void:
	_expect(Net._spectator_drones.has(target), "other players receive the drone")
	_expect(Net._spectator_drones[target].visible, "other players see the drone")
	rpc_id(1, "checked", "player drone")


@rpc("authority", "reliable")
func leave_spectating() -> void:
	Net.leave_game()
	finish()


@rpc("authority", "reliable")
func check_live(first: int, second: int) -> void:
	_expect(_body(1).position.distance_to(Vector3(-12, 6, -5)) < 0.1, "live host movement")
	_expect(absf(_body(1).rotation.y - 0.8) < 0.01, "live host rotation")
	_expect(_body(first).position.distance_to(Vector3(10, 6, 4)) < 0.1, "live client movement")
	_expect(not _body(second)._unconscious, "live revive")
	_expect(_body(1)._anim_player.assigned_animation == "dodge_left", "live dodge animation")
	_expect(get_tree().current_scene.get_node("water base")._walls.is_empty(), "wall release")
	_expect(Net._round_blue_score == 1, "revive keeps round score")
	_expect(get_tree().current_scene.get_node("PushCube").position.distance_to(Vector3(18, 8, 7)) < 0.1, "live prop movement")
	_expect(not Net._spectator_drones[1].visible, "moving drone stays hidden from spectators")
	rpc_id(1, "checked", "live")


@rpc("authority", "reliable")
func check_wave() -> void:
	_expect(not get_tree().current_scene.get_node("water base").get_active_waves().is_empty(), "live water move")
	_expect(_body(1)._anim_player.assigned_animation == "water_power", "live move animation")
	rpc_id(1, "checked", "wave")


@rpc("authority", "reliable")
func check_drone() -> void:
	_expect(Net._spectator_camera._living_lifeguard() == null, "drone after lifeguards faint")
	rpc_id(1, "checked", "drone")


@rpc("authority", "reliable")
func check_score(first: int) -> void:
	_expect(Net._round_blue_score == 2, "live scoreboard score")
	_expect(get_tree().current_scene.get_node("Scoreboard").blue_score.text == "2", "live scoreboard label")
	_expect(Net._spectator_camera._living_lifeguard() == _body(first), "switch to surviving lifeguard")
	for drone in Net._spectator_drones.values():
		_expect(not drone.visible, "departing drones stay hidden from spectators")
	rpc_id(1, "checked", "score")


@rpc("authority", "reliable")
func check_next_round() -> void:
	_expect(_players().size() == 3, "spectator receives next round players")
	_expect(Net._round_blue_score == 0 and Net._round_red_score == 0, "round score resets")
	_expect(Net._spectator_camera._living_lifeguard() != null, "next round lifeguard")
	rpc_id(1, "checked", "next round")


@rpc("any_peer", "reliable")
func checked(stage: String) -> void:
	checks[stage] = true
	print("PASS ", stage)


@rpc("authority", "reliable")
func finish() -> void:
	print("PASS match replication ", role)
	get_tree().quit(1 if failed else 0)


func _players() -> Array:
	var players := Net._players_root()
	return players.get_children() if players else []


func _body(id: int) -> Node:
	var players := Net._players_root()
	return players.get_node_or_null(str(id)) if players else null


func _until(condition: Callable) -> void:
	while not condition.call():
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failed = true
	push_error("FAIL %s: %s" % [role, message])
	get_tree().quit(1)
