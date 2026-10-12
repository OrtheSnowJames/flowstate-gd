extends Node

var role := "host"
var client := 0
var spectator := 0
var checks: Dictionary = {}
var failed := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			role = arg.trim_prefix("--test=")
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	Settings.player_name = "Cube " + role
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("FAIL cube replication timeout " + role)
		get_tree().quit(1))
	if role == "host":
		await _host()
		return
	Net._connect_flow_active = true
	_expect(Net.join_game("127.0.0.1", 18095) == OK, "join starts")
	await multiplayer.connected_to_server
	rpc_id(1, "register", role)
	if role == "spectator":
		await _until(func() -> bool: return Net._connection_game_in_progress)
		_choose_spectate()
		await Net._show_game_in_progress_prompt()
	else:
		await _until(func() -> bool: return _body(multiplayer.get_unique_id()) != null)
		var local := _body(multiplayer.get_unique_id())
		local.freeze = true
		local.set_physics_process(false)
	await _until(func() -> bool: return _body(1) != null)
	rpc_id(1, "checked", "ready")


func _host() -> void:
	_expect(Net.host_game(18095, false, Net.GameMode.KING_OF_CUBE) == OK, "host starts")
	await _until(func() -> bool: return client > 0)
	Net._teams = {1: 0, client: 1}
	Net._broadcast_roster()
	Net.start_round()
	await _until(func() -> bool: return Net._round_started and checks.has("ready"))
	var host := _body(1)
	host.freeze = true
	host.set_physics_process(false)
	var cube := get_tree().current_scene.get_node("PushCube")
	cube.freeze = true
	cube.position = Vector3(12, 10, 0)
	cube.rotation = Vector3.ZERO
	host.position = Vector3(12, 11.82, 0)
	await _until(func() -> bool: return Net._round_red_score == 2)
	var controller := cube.get_node("KingOfCube")
	controller.set_physics_process(false)
	print("READY_FOR_SPECTATOR")
	await _until(func() -> bool: return spectator > 0 and checks.get("ready", []).has(spectator))
	await _verify("late join", Net.CubeControl.RED, 2, 0)
	rpc_id(client, "move", Vector3(11.5, 11.82, 0))
	controller.set_physics_process(true)
	await _until(func() -> bool: return Net.cube_control == Net.CubeControl.CONTESTED)
	await get_tree().create_timer(1.2).timeout
	await _verify("contested", Net.CubeControl.CONTESTED, 2, 0)
	host.position = Vector3(16, 12, 0)
	await _until(func() -> bool: return Net._round_blue_score == 1)
	controller.set_physics_process(false)
	await _verify("blue capture", Net.CubeControl.BLUE, 2, 1)
	rpc_id(client, "faint")
	controller.set_physics_process(true)
	await _until(func() -> bool: return _body(client)._unconscious)
	await _until(func() -> bool: return not _body(client)._unconscious)
	await get_tree().create_timer(0.4).timeout
	_expect(_body(client).position.distance_to(Net.spawn_position(client)) < 0.1, "respawn position replicates")
	_expect(_body(client).position.z > 0.0, "blue client respawns on blue side")
	await _verify("respawn", Net.CubeControl.NEUTRAL, 2, 1)
	_expect(not Net._round_over, "faint does not end cube round")
	host._muffled_player = null
	host.blackout_time = 0.1
	host._death()
	await _until(func() -> bool: return not host._unconscious)
	_expect(host.position.distance_to(Net.spawn_position(1)) < 0.1 and host.position.z < 0.0, "red host respawns on red side")
	_expect(not Net.is_spectating() and host.stamina == host.max_stamina, "host respawn restores view and stamina")
	await _verify("host respawn", Net.CubeControl.NEUTRAL, 2, 1)
	controller.set_physics_process(false)
	cube.get_node("Buoyancy").set_physics_process(false)
	cube.position = Vector3(12, 14, 0)
	cube.linear_velocity = Vector3.ZERO
	cube.gravity_scale = 0.0
	cube.freeze = false
	await get_tree().create_timer(0.3).timeout
	rpc_id(client, "push_cube")
	await _until(func() -> bool: return checks.has("pushed"))
	_expect(cube.position.x > 12.2, "client contact moves the host cube")
	_expect(cube._last_push.has(client), "host receives client contact impulses")
	rpc("verify_push")
	await _until(func() -> bool: return checks.get("push visible", []).size() == 2)
	print("PASS client cube push")
	Net._round_red_score = 99
	Net.award_cube_point(0)
	await _until(func() -> bool: return Net.round_state == Net.RoundState.LOBBY)
	await get_tree().create_timer(1.0).timeout
	Net.start_round()
	await _until(func() -> bool: return Net._round_started)
	await _verify("next round", Net.CubeControl.NEUTRAL, 0, 0)
	rpc("finish")
	finish()


func _verify(stage: String, control: int, red: int, blue: int) -> void:
	await get_tree().create_timer(0.2).timeout
	_expect(Net.cube_control == control and Net._round_red_score == red and Net._round_blue_score == blue, stage + " host state")
	rpc("verify", stage, control, red, blue)
	await _until(func() -> bool: return checks.get(stage, []).size() == 2)
	print("PASS cube ", stage)


@rpc("authority", "reliable")
func verify(stage: String, control: int, red: int, blue: int) -> void:
	_expect(Net.game_mode == Net.GameMode.KING_OF_CUBE, stage + " mode")
	_expect(Net.cube_control == control, stage + " control")
	_expect(Net._round_red_score == red and Net._round_blue_score == blue, stage + " scores")
	var scene := get_tree().current_scene
	_expect(scene.get_node("Scoreboard").red_goal.text == "Goal: 100 points", stage + " goal")
	var controller := scene.get_node("PushCube/KingOfCube")
	_expect(controller._material.albedo_color == controller.COLORS[control], stage + " cube material")
	Net.award_cube_point(0)
	_expect(Net._round_red_score == red, "clients cannot award points")
	if stage == "respawn" and role == "client":
		_expect(not Net.is_spectating() and not _body(multiplayer.get_unique_id())._unconscious, "respawn restores player view")
	if stage == "respawn":
		for player in Net._players_root().get_children():
			if player.team == Net.PLAYER_SCRIPT.Team.BLUE:
				_expect(player.position.z > 0.0 and not player._unconscious, "blue team respawn is visible to all peers")
	if stage == "host respawn":
		_expect(_body(1).position.z < 0.0 and not _body(1)._unconscious, "red team respawn is visible to all peers")
	rpc_id(1, "checked", stage)


@rpc("authority", "reliable")
func push_cube() -> void:
	var local := _body(multiplayer.get_unique_id())
	var cube := get_tree().current_scene.get_node("PushCube")
	local.position = cube.position + Vector3(-1.5, 0, 0)
	local.gravity_scale = 0.0
	local.freeze = false
	for i in range(60):
		local.linear_velocity = Vector3(3, 0, 0)
		await get_tree().physics_frame
	local.freeze = true
	rpc_id(1, "checked", "pushed")


@rpc("authority", "reliable")
func verify_push() -> void:
	await get_tree().create_timer(0.2).timeout
	_expect(get_tree().current_scene.get_node("PushCube").position.x > 12.2, "client push is visible to " + role)
	rpc_id(1, "checked", "push visible")


@rpc("authority", "reliable")
func move(pos: Vector3) -> void:
	_body(multiplayer.get_unique_id()).position = pos


@rpc("authority", "reliable")
func faint() -> void:
	var local := _body(multiplayer.get_unique_id())
	local._muffled_player = null
	local.blackout_time = 0.1
	local._death()


@rpc("any_peer", "reliable")
func register(value: String) -> void:
	if value == "client":
		client = multiplayer.get_remote_sender_id()
	else:
		spectator = multiplayer.get_remote_sender_id()


@rpc("any_peer", "reliable")
func checked(stage: String) -> void:
	if not checks.has(stage):
		checks[stage] = []
	checks[stage].append(multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func finish() -> void:
	print("%s cube replication %s" % ["FAIL" if failed else "PASS", role])
	get_tree().quit(1 if failed else 0)


func _choose_spectate() -> void:
	await _until(func() -> bool: return Transition.has_node("DisconnectPrompt"))
	Transition.get_node("DisconnectPrompt")._choose(true)


func _body(id: int) -> Node:
	var players := Net._players_root()
	return players.get_node_or_null(str(id)) if players else null


func _until(condition: Callable) -> void:
	while not condition.call():
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL %s %s" % [role, message])
