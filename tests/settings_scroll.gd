extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(20.0).timeout.connect(func() -> void: get_tree().quit(1))
	var menu: Node = load("res://menu/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.8).timeout
	print("settings test root ready")
	var screen: Control = menu._menu_screen
	var scroll: ScrollContainer = screen.get_parent()
	screen._buttons[1].pressed.emit()
	await get_tree().create_timer(1.0).timeout
	print("settings test list ready")
	for viewport_size in [Vector2i(1152, 648), Vector2i(640, 480)]:
		get_window().size = viewport_size
		print("settings test viewport ", viewport_size)
		await get_tree().create_timer(0.2).timeout
		scroll.scroll_vertical = 0
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(scroll.get_v_scroll_bar().visible, "long settings list has a scrollbar")
		_expect(screen._buttons[0].get_global_rect().position.y >= scroll.get_global_rect().position.y, "first setting is reachable")
		var wheel := InputEventMouseButton.new()
		wheel.position = screen._buttons[0].get_global_rect().get_center()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		get_viewport().push_input(wheel, true)
		await get_tree().process_frame
		_expect(scroll.scroll_vertical > 0, "wheel scrolls over a setting button")
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		var back: Control = screen._buttons.back()
		_expect(scroll.get_global_rect().encloses(back.get_global_rect()), "back button is reachable at the bottom")
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.1).timeout
			RenderingServer.force_draw()
			var frame := get_viewport().get_texture().get_image()
			frame.save_png("/tmp/flowstate-settings-%d.png" % viewport_size.x)
			var visible_samples := 0
			for y in range(0, frame.get_height(), 16):
				for x in range(0, frame.get_width(), 16):
					if frame.get_pixel(x, y).get_luminance() > 0.05:
						visible_samples += 1
			_expect(visible_samples > 20, "settings screenshot is not blank")
		var saved_scroll := scroll.scroll_vertical
		menu._show_settings()
		await get_tree().create_timer(1.0).timeout
		_expect(scroll.scroll_vertical == saved_scroll, "refresh preserves scroll position")
	screen._buttons.back().pressed.emit()
	await get_tree().create_timer(0.8).timeout
	_expect(scroll.scroll_vertical == 0, "returning to root resets scrolling")
	_expect(not scroll.get_v_scroll_bar().visible, "short menu stays centered without scrolling")
	print("PASS settings scrolling" if not failed else "FAIL settings scrolling")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
