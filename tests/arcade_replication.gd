extends Node

var client := 0
var checks: Dictionary = {}
var failed := false
var role := "host"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--client":
			role = "client"
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(40).timeout.connect(func():
		push_error("FAIL arcade replication timeout " + role)
		get_tree().quit(1))
	if role == "client":
		Net._connect_flow_active = true
		Net.join_game("127.0.0.1", 18106)
		await multiplayer.connected_to_server
		rpc_id(1, "register")
		return
	Net.host_game(18106, false, Net.GameMode.ARCADE)
	await _until(func(): return client != 0)
	Net._teams = {1: 0, client: 1}
	Net._broadcast_roster()
	Net.start_round()
	await _until(func(): return Net._round_started)
	prepare(Vector3(-5, 20, 0))
	rpc_id(client, "prepare", Vector3(5, 20, 0))
	await _until(func(): return checks.has("ready"))
	await get_tree().create_timer(0.5).timeout
	Net.arcade.submit(1, Net.arcade.Action.Q, client)
	rpc_id(client, "dash")
	await _until(func(): return Net.arcade.states.get(1, {}).get("phase", -1) == Net.arcade.Phase.CLASH)
	Net.arcade.set_physics_process(false)
	await get_tree().create_timer(0.2).timeout
	rpc_id(client, "verify_clash")
	await _until(func(): return checks.has("clash"))
	await _until(func(): return Net.arcade.states[client].phase == Net.arcade.Phase.SLAM)
	_expect(Net.arcade.states[1].phase == Net.arcade.Phase.OPEN, "client wrong key reaches host")
	Net.arcade.states[1].position = Vector3(0, 24, 0)
	Net.arcade.states[client].position = Vector3(0, 20, 0)
	Net.arcade._set_phase(Net.arcade.states[client], Net.arcade.Phase.OPEN, 1.5)
	Net.arcade._publish(true)
	await get_tree().create_timer(0.2).timeout
	Net.arcade.submit(1, Net.arcade.Action.POUND, client)
	Net.arcade.set_physics_process(true)
	await _until(func(): return Net.arcade.states.is_empty())
	await get_tree().create_timer(0.3).timeout
	rpc_id(client, "verify_damage")
	await _until(func(): return checks.has("damage"))
	rpc_id(client, "finish")
	await get_tree().create_timer(0.2).timeout
	finish()


@rpc("any_peer", "reliable")
func register() -> void:
	client = multiplayer.get_remote_sender_id()


@rpc("authority", "reliable")
func prepare(pos: Vector3) -> void:
	var player = Net.arcade._body(multiplayer.get_unique_id())
	player.freeze = true
	player.set_physics_process(false)
	player.position = pos
	player.stamina = 200
	if role == "client":
		rpc_id(1, "checked", "ready")


@rpc("authority", "reliable")
func dash() -> void:
	Net.arcade.request_action(Net.arcade.Action.Q, 1, 0)


@rpc("authority", "reliable")
func verify_clash() -> void:
	var id := multiplayer.get_unique_id()
	_expect(Net.game_mode == Net.GameMode.ARCADE, "mode replicates")
	_expect(Net.arcade.view[id].phase == Net.arcade.Phase.CLASH, "clash replicates")
	_expect(Net.arcade.controls(Net.arcade._body(id)), "client movement controlled")
	_expect(Net.arcade._body(id).position.distance_to(Net.arcade.view[id].position) < 0.2, "client position interpolates")
	Net.arcade.request_action(Net.arcade.Action.E, 0, Net.arcade.view[id].fight)
	rpc_id(1, "checked", "clash")


@rpc("authority", "reliable")
func verify_damage() -> void:
	var player = Net.arcade._body(multiplayer.get_unique_id())
	_expect(player.stamina == 125, "pound damage reaches client once")
	_expect(not Net.arcade.controls(player), "client released after pound")
	rpc_id(1, "checked", "damage")


@rpc("any_peer", "reliable")
func checked(stage: String) -> void:
	checks[stage] = true


@rpc("authority", "reliable")
func finish() -> void:
	print(("FAIL" if failed else "PASS") + " arcade replication " + role)
	get_tree().quit(1 if failed else 0)


func _until(condition: Callable) -> void:
	while not condition.call():
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + role + " " + message)
