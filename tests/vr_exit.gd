extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(25).timeout.connect(func():
		push_error("FAIL vr exit timeout")
		get_tree().quit(1))
	await get_tree().create_timer(0.8).timeout
	_expect(_button("Quit") != null and _button("Enter VR") != null, "desktop offers quit and enter vr")
	_expect(VR.start(true), "couch preview starts")
	await get_tree().create_timer(0.8).timeout
	_expect(_button("Quit") != null and _button("Exit VR") == null, "couch offers quit instead of exit vr")
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		RenderingServer.force_draw()
		VR.room_view.get_texture().get_image().save_png("/tmp/flowstate-vr-before-return.png")
	var viewport_id := VR.room_view.get_instance_id()
	var room_id := VR._room.get_instance_id()
	var head_id := VR._head.get_instance_id()
	for cycle in range(2):
		_button("Real VR").pressed.emit()
		await get_tree().create_timer(1.3).timeout
		_expect(VR.immersive and not VR.entering, "real vr button enters immersive view")
		_expect(_button("Exit VR") != null and _button("Quit") == null, "immersive menu offers return to room")
		VR._head.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(3, 1.7, -2))
		_button("Exit VR").pressed.emit()
		_expect(VR.exiting and VR.active, "exit starts a transition without stopping xr")
		VR.exit_immersive()
		VR.enter_immersive()
		await get_tree().create_timer(0.35).timeout
		_expect(VR.exiting and not VR.immersive, "return pulls back through the room")
		var moving_from: Vector3 = VR._origin.position
		await get_tree().create_timer(0.2).timeout
		_expect(VR._origin.position.distance_to(moving_from) > 0.05, "return camera moves away from the tv")
		await get_tree().create_timer(0.65).timeout
		_expect(VR.active and not VR.immersive and not VR.exiting, "return finishes in couch mode")
		_expect(VR.room_view.get_instance_id() == viewport_id and VR._head.get_instance_id() == head_id, "headset and viewport persist across transitions")
		_expect(VR._room.get_instance_id() == room_id and VR._room.is_inside_tree(), "living room is reused")
		_expect(VR.room_view.own_world_3d and VR.room_view.find_world_3d() != get_tree().root.world_3d, "room does not share the pool world")
		_expect(VR._environment.environment != null and VR._light.visible, "room lighting returns")
		_expect(VR._head.global_position.distance_to(VR._room.get_node("SeatEye").global_position) < 0.001, "offset headset returns to the couch seat")
		_expect(not get_tree().root.disable_3d and not get_tree().root.transparent_bg, "game rendering returns to the tv")
		_expect(Transition._fade_rect.visible and Transition._blur_rect.visible, "screen overlays are restored")
		_expect(VR.immersion == null and VR._head.get_child_count() == 0, "immersive panels and fade are removed")
		_expect(_button("Quit") != null and _button("Real VR") != null and _button("Exit VR") == null, "couch menu returns after exit")
		var screen = VR._room.get_node("GameScreen")
		_expect(screen.material_override.albedo_texture == get_tree().root.get_texture(), "tv shows the live menu")
		if DisplayServer.get_name() != "headless":
			# the tv samples the previous frame of the main viewport
			RenderingServer.force_draw()
			RenderingServer.force_draw()
			var picture := VR.room_view.get_texture().get_image()
			picture.save_png("/tmp/flowstate-vr-return-%d.png" % cycle)
			get_tree().root.get_texture().get_image().save_png("/tmp/flowstate-vr-return-tv-%d.png" % cycle)
			var tv_center: Vector2 = VR._head.unproject_position(screen.global_position)
			var blue := 0
			for y in range(int(tv_center.y) - 60, int(tv_center.y) + 60):
				for x in range(int(tv_center.x) - 120, int(tv_center.x) + 120):
					var pixel := picture.get_pixel(x, y)
					if pixel.b > 0.5 and pixel.b > pixel.r * 1.3 and pixel.g > pixel.r * 1.2:
						blue += 1
			_expect(blue > 100, "returned tv displays the blue menu buttons")
			var different := 0
			var first := picture.get_pixel(0, 0)
			for y in range(0, picture.get_height(), 8):
				for x in range(0, picture.get_width(), 8):
					if picture.get_pixel(x, y) != first:
						different += 1
			_expect(different > 300, "returned room is not blank")
	VR.stop()
	_expect(VR.start(true), "vr can restart immediately after stopping")
	await get_tree().create_timer(0.8).timeout
	if failed:
		get_tree().quit(1)
		return
	print("PASS vr return transition and menu buttons")
	_button("Quit").pressed.emit()


func _button(label: String) -> Control:
	for button in get_parent().get_node("UI/MenuScroll/MenuScreen")._buttons:
		if button.button_text == label:
			return button
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
