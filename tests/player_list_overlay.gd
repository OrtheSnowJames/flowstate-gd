extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Settings.player_name = "Host"
	Net._teams = {1: 0, 2: 1}
	Net._names = {1: "Host", 2: "Guest"}
	var lobby: Node = load("res://menu/lobby.tscn").instantiate()
	add_child(lobby)
	await get_tree().create_timer(0.7).timeout
	lobby._menu_screen._buttons[1].pressed.emit()
	await get_tree().create_timer(0.8).timeout
	var list := Transition.get_node_or_null("PlayerList")
	if list == null:
		_expect(false, "player list is above the global blur")
		get_tree().quit(1)
		return
	_expect(list.visible, "player list opens")
	_expect(list.get_index() > Transition._blur_rect.get_index(), "list is drawn after blur")
	_expect(list._rows.get_child_count() == 2, "both players appear")
	_expect(is_equal_approx(float(Transition._blur_mat.get_shader_parameter("amount")), 1.0), "background is blurred")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/flowstate-player-list.png")
	Net._names[2] = "Updated Guest"
	Net.lobby_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(list._rows.get_child(1).text == "Updated Guest", "roster updates while open")
	list._button_host._buttons[0].pressed.emit()
	await get_tree().create_timer(0.5).timeout
	_expect(not is_instance_valid(list), "close removes list")
	_expect(is_zero_approx(float(Transition._blur_mat.get_shader_parameter("amount"))), "close clears blur")
	lobby._on_view_players()
	await get_tree().create_timer(0.8).timeout
	list = Transition.get_node("PlayerList")
	lobby.queue_free()
	await get_tree().create_timer(0.5).timeout
	_expect(not is_instance_valid(list), "leaving lobby removes list")
	_expect(is_zero_approx(float(Transition._blur_mat.get_shader_parameter("amount"))), "leaving lobby clears blur")
	print("PASS player list overlay" if not failed else "FAIL player list overlay")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
