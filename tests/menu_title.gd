extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().change_scene_to_file(Net.MENU_SCENE)
	await get_tree().create_timer(1.0).timeout
	var menu := get_tree().current_scene
	var screen: Control = menu._menu_screen
	for window_size in [Vector2i(1152, 648), Vector2i(640, 480), Vector2i(390, 844)]:
		get_window().size = window_size
		await get_tree().create_timer(0.5).timeout
		_expect(screen._heading.visible and screen._heading.text == "FLOWSTATE", "root shows title")
		_expect(screen._heading.get_rect().end.y <= screen._buttons[0].position.y, "title clears play button")
		_expect(screen._heading.size.x <= screen.size.x, "title fits menu width")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/flowstate-title-%d.png" % window_size.x)
	menu._show_play()
	await get_tree().create_timer(0.8).timeout
	_expect(not screen._heading.visible, "play submenu stays unchanged")
	menu._show_root()
	await get_tree().create_timer(0.8).timeout
	_expect(screen._heading.visible, "back restores title")
	menu._show_settings()
	await get_tree().create_timer(0.8).timeout
	_expect(not screen._heading.visible, "settings stays unchanged")
	print("%s menu title" % ["FAIL" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
