extends Node

var failed := false
var role := "unit"
var started := false
var penalty := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--timeout-role="):
			role = arg.trim_prefix("--timeout-role=")
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(55.0).timeout.connect(func() -> void:
		push_error("FAIL black screen test timed out")
		get_tree().quit(1))
	penalty = Settings.online_penalty_until_unix
	if role == "unit":
		await _unit_checks()
	elif role == "host":
		_expect(Net.host_game(Net.PORT, true) == OK, "host starts")
		Matchmaking._webrtc = true
		Matchmaking._host_port = Net.PORT
		_expect(await Matchmaking._register_room(Matchmaking._generation), "room registers")
		print("TIMEOUT_HOST_READY ", Net.room_code)
		while Net.lobby_count() < 3:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		rpc("start_black_test")
		await _check_disconnected()
	else:
		await Matchmaking.join_code(OS.get_environment("FLOWSTATE_TEST_CODE"))
		_expect(Net.is_online(), "client joins")
		while not started:
			await get_tree().process_frame
		await _check_disconnected()
	print("%s black screen timeout %s" % ["FAIL" if failed else "PASS", role])
	get_tree().quit(1 if failed else 0)


@rpc("authority", "call_local", "reliable")
func start_black_test() -> void:
	started = true
	# only one client hangs so the others must receive the abort
	if role != "stalled":
		return
	await Transition.blur_in()
	await Transition.show_status("Loading...")
	await Transition.fade_to_black()
	var since := Time.get_ticks_msec()
	while Net.is_online():
		await get_tree().process_frame
	_expect(Time.get_ticks_msec() - since >= 19500, "timeout waits twenty real seconds")


func _check_disconnected() -> void:
	while Net.is_online():
		await get_tree().process_frame
	while Net._leaving_game or Net._load_timeout_closing:
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	_check_menu()
	_expect(Matchmaking.rtc.peer == null, "webrtc transport closes")
	_expect(Matchmaking._host_token.is_empty(), "room token clears")


func _unit_checks() -> void:
	Transition.set_process(false)
	await Transition.fade_to_black()
	Transition._check_black_screen(100000)
	Transition._check_black_screen(119999)
	_expect(not Net._load_timeout_closing, "nineteen seconds does not abort")
	await Transition.fade_from_black()
	Transition._check_black_screen(120000)
	_expect(Transition._black_since_msec == -1, "visible screen cancels watchdog")
	await Transition.fade_to_black()
	Transition._check_black_screen(200000)
	Transition._check_black_screen(200001)
	_expect(not Net._load_timeout_closing, "new fade gets a fresh deadline")
	# an old scene change must not resume after recovery
	Net._load_arena()
	get_tree().paused = true
	Transition._check_black_screen(220000)
	while Net._load_timeout_closing:
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	_check_menu()
	_expect(not get_tree().paused, "recovery unpauses")
	Transition.set_process(true)
	_expect(Transition.process_mode == Node.PROCESS_MODE_ALWAYS, "watchdog runs while paused")


func _check_menu() -> void:
	_expect(multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "session disconnects")
	_expect(get_tree().current_scene.scene_file_path == Net.MENU_SCENE, "returns to main menu")
	_expect(Transition._fade_rect.color.a == 0.0, "black overlay clears")
	_expect(Transition._blur_mat.get_shader_parameter("amount") == 0.0, "blur clears")
	_expect(Transition._status_label.modulate.a == 0.0, "loading text clears")
	_expect(Settings.online_penalty_until_unix == penalty, "no disconnect penalty")
	_expect(not Matchmaking.busy and not Net.input_blocked_by_menu(), "menu accepts input")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
