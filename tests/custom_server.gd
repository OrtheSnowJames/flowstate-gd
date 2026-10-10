extends Node

const TEST_PORT := 18091
var failed := false
var submitted: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("FAIL custom server timeout")
		get_tree().quit(1))
	Settings.player_name = "Custom Server Test"
	var role := "ui"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--custom-test="):
			role = arg.trim_prefix("--custom-test=")
	get_tree().change_scene_to_file(Net.MENU_SCENE)
	await get_tree().create_timer(0.8).timeout
	var menu := get_tree().current_scene
	menu._menu_screen._buttons[0].pressed.emit()
	await get_tree().create_timer(0.8).timeout
	_expect(menu._menu_screen._buttons[4].button_text == "Custom Server", "play includes custom server")
	menu._menu_screen._buttons[4].pressed.emit()
	await get_tree().create_timer(0.8).timeout
	menu._menu_screen._buttons[1 if role == "host" else 0].pressed.emit()
	await get_tree().create_timer(0.8).timeout
	var prompt := menu.get_node("UI/ServerPrompt")
	if role == "ui":
		await _test_form(menu, prompt)
	elif role == "host" or role == "join":
		prompt._port.text = str(TEST_PORT)
		prompt._buttons._buttons[0].pressed.emit()
		if role == "host":
			await get_tree().create_timer(1.0).timeout
			_expect(get_tree().current_scene.scene_file_path == Net.LOBBY_SCENE, "custom host opens lobby")
			_expect(multiplayer.is_server() and Net.is_online(), "custom host is online")
			print("CUSTOM_HOST_READY")
		while Net.lobby_count() < 2:
			await get_tree().process_frame
		_expect(get_tree().current_scene.scene_file_path == Net.LOBBY_SCENE, "custom connection enters lobby")
		if role == "host":
			while Net.lobby_count() > 1:
				await get_tree().process_frame
		else:
			await get_tree().create_timer(1.0).timeout
		Net.leave_game()
	elif role == "busy":
		prompt.queue_free()
		var blocker := ENetMultiplayerPeer.new()
		_expect(blocker.create_server(TEST_PORT) == OK, "reserve test port")
		await Net.start_host_lobby(TEST_PORT)
		_expect(get_tree().current_scene == menu, "failed host stays in menu")
		_expect(not Net.is_online(), "failed host stays offline")
		blocker.close()
	elif role == "unreachable":
		prompt._port.text = str(TEST_PORT)
		prompt._buttons._buttons[0].pressed.emit()
		await get_tree().create_timer(12.0).timeout
		_expect(get_tree().current_scene.scene_file_path == Net.MENU_SCENE, "failed join returns to menu")
		_expect(multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "failed join closes pending peer")
	print("%s custom server %s" % ["FAIL" if failed else "PASS", role])
	get_tree().quit(1 if failed else 0)


func _test_form(menu: Node, prompt: Control) -> void:
	for connection in prompt.submitted.get_connections():
		prompt.submitted.disconnect(connection.callable)
	prompt.submitted.connect(func(ip: String, port: int) -> void: submitted.append([ip, port]))
	_expect(prompt._address_row.visible, "join shows address")
	_expect(prompt._port.text == str(Net.PORT), "port defaults to existing port")
	prompt._address.text = " "
	prompt._submit()
	_expect(not prompt._error.text.is_empty() and submitted.is_empty(), "blank address is rejected")
	prompt._address.text = " 127.0.0.1 "
	for invalid in ["", "0", "-1", "65536", "abc", "7.5"]:
		prompt._port.text = invalid
		prompt._submit()
		_expect(submitted.is_empty(), "invalid port is rejected " + invalid)
	for viewport_size in [Vector2i(1152, 648), Vector2i(640, 480)]:
		get_window().size = viewport_size
		await get_tree().create_timer(0.3).timeout
		var scroll: ScrollContainer = prompt.get_node("Margin/Scroll")
		_expect(prompt._panel.size.x <= scroll.size.x, "form fits viewport width")
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		_expect(scroll.get_global_rect().encloses(prompt._buttons._buttons.back().get_global_rect()), "cancel remains reachable")
		if DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png("/tmp/flowstate-custom-server-%d.png" % viewport_size.x)
	prompt._port.text = str(TEST_PORT)
	prompt._port.text_submitted.emit(str(TEST_PORT))
	_expect(submitted == [["127.0.0.1", TEST_PORT]], "enter submits trimmed address and custom port")
	prompt._submit()
	_expect(submitted.size() == 1, "duplicate submission is ignored")
	await get_tree().process_frame
	menu._menu_screen._buttons[1].pressed.emit()
	await get_tree().create_timer(0.8).timeout
	var host_prompt := menu.get_node("UI/ServerPrompt")
	_expect(not host_prompt._address_row.visible, "hosting only asks for port")
	host_prompt._buttons._buttons[1].pressed.emit()
	await get_tree().process_frame
	_expect(not menu.has_node("UI/ServerPrompt"), "cancel closes prompt")
	menu._menu_screen._buttons[2].pressed.emit()
	await get_tree().create_timer(0.8).timeout
	_expect(menu._menu_screen._buttons[0].button_text == "Quick Play", "back returns to play")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
