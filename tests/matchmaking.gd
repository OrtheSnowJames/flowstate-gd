extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(50.0).timeout.connect(func() -> void:
		push_error("FAIL matchmaking timeout")
		get_tree().quit(1))
	Settings.player_name = "Matchmaking Test"
	var role := "ui"
	var code := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--match-test="):
			role = arg.trim_prefix("--match-test=")
		if arg.begins_with("--code="):
			code = arg.trim_prefix("--code=")
	get_tree().change_scene_to_file(Net.MENU_SCENE)
	await get_tree().create_timer(0.8).timeout
	var menu := get_tree().current_scene
	menu._menu_screen._buttons[0].pressed.emit()
	await get_tree().create_timer(1.0).timeout
	_expect(menu._menu_screen._buttons[0].button_text == "Quick Play", "quick play is first")
	_expect(menu._menu_screen._buttons[1].button_text == "Join Code", "join code is second")
	if role == "ui":
		await _test_ui(menu)
	elif role == "host":
		menu._menu_screen._buttons[0].pressed.emit()
		while Matchmaking.busy:
			await get_tree().process_frame
		_expect(Net.is_online() and multiplayer.is_server(), "empty quick play creates a host")
		_expect(Matchmaking.valid_code(Net.room_code), "host has room code")
		code = Net.room_code
		_expect(get_tree().current_scene.get_node("UI/RoomCode").text.contains(code), "lobby displays code")
		print("MATCH_HOST_READY ", code)
		while Net.lobby_count() < 3:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		var result: Dictionary = await Matchmaking._request(HTTPClient.METHOD_GET, "/rooms/" + code)
		_expect(result.status == 200 and result.data.players == 3, "heartbeat updates occupancy")
		Net.round_state = Net.RoundState.PLAYING
		Matchmaking.mark_dirty()
		await get_tree().create_timer(0.5).timeout
		result = await Matchmaking._request(HTTPClient.METHOD_POST, "/matchmaking", {"protocol": Matchmaking.PROTOCOL})
		_expect(result.status == 404, "started match leaves quick play")
		result = await Matchmaking._request(HTTPClient.METHOD_GET, "/rooms/" + code)
		_expect(result.status == 200 and result.data.state == "in_game", "started match still resolves by code")
		Net.leave_game()
		await get_tree().create_timer(0.5).timeout
		result = await Matchmaking._request(HTTPClient.METHOD_GET, "/rooms/" + code)
		_expect(result.status == 404, "leaving removes room")
	elif role in ["quick", "code"]:
		if role == "quick":
			await Matchmaking.quick_play()
		else:
			menu._menu_screen._buttons[1].pressed.emit()
			await get_tree().create_timer(0.8).timeout
			var prompt := menu.get_node("UI/ServerPrompt")
			prompt._address.text = code.to_lower()
			prompt._submit()
			while Matchmaking.busy:
				await get_tree().process_frame
		_expect(Net.is_online() and not multiplayer.is_server(), "matchmaking connects to player host")
		_expect(Net.room_code == code, "room code replicates to clients")
		while Net.lobby_count() < 3:
			await get_tree().process_frame
		while Net.is_online():
			await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
		_expect(get_tree().current_scene.scene_file_path == Net.MENU_SCENE, "host departure returns clients to menu")
	print("%s matchmaking %s" % ["FAIL" if failed else "PASS", role])
	get_tree().quit(1 if failed else 0)


func _test_ui(menu: Node) -> void:
	for viewport_size in [Vector2i(1152, 648), Vector2i(640, 480)]:
		get_window().size = viewport_size
		await get_tree().create_timer(0.3).timeout
		menu._menu_screen.get_parent().scroll_vertical = 0
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png("/tmp/flowstate-matchmaking-menu-%d.png" % viewport_size.x)
	menu._menu_screen._buttons[1].pressed.emit()
	await get_tree().create_timer(0.8).timeout
	var prompt := menu.get_node("UI/ServerPrompt")
	_expect(not prompt._port.get_parent().visible, "join code only asks for code")
	prompt._address.text = "bad"
	prompt._submit()
	_expect(not prompt._error.text.is_empty(), "invalid code stays in form")
	prompt._buttons._buttons[1].pressed.emit()
	await get_tree().process_frame
	var old_endpoint: String = Matchmaking.endpoint
	Matchmaking.endpoint = ""
	await Matchmaking.quick_play()
	_expect(not Net.is_online() and not Matchmaking.busy, "missing endpoint exits cleanly")
	Matchmaking.endpoint = old_endpoint
	var old_penalty: int = Settings.online_penalty_until_unix
	Settings.online_penalty_until_unix = int(Time.get_unix_time_from_system()) + 60
	await Matchmaking.quick_play()
	await Matchmaking.join_code("ABC234")
	_expect(not Net.is_online() and not Matchmaking.busy, "penalty blocks matchmaking")
	await get_tree().create_timer(2.5).timeout
	Settings.online_penalty_until_unix = old_penalty


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
