extends RefCounted


static func track(player, event: InputEvent) -> void:
	if VR.active:
		if not player.using_controller:
			player.controller_angles = Vector2(player._cam_pivot.global_rotation.y, player._camera.rotation.x)
		player.using_controller = true
		return
	var using_pad: bool = player.using_controller
	if event is InputEventJoypadButton and event.pressed:
		using_pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.25:
		using_pad = true
	elif event is InputEventKey and event.pressed or event is InputEventMouseButton and event.pressed:
		using_pad = false
	elif event is InputEventMouseMotion and event.relative.length() > 2.0:
		using_pad = false
	if using_pad and not player.using_controller:
		player.controller_angles = Vector2(player._cam_pivot.global_rotation.y, player._camera.rotation.x)
	player.using_controller = using_pad


static func move_input() -> Vector2:
	return Input.get_vector("pad_move_left", "pad_move_right", "pad_move_up", "pad_move_down")


static func movement_input(player) -> Vector2:
	if player.using_controller:
		return Vector2(0.0, -move_input().length())
	return Vector2(0.0, Input.get_axis("forward", "back"))


static func aim_position(player) -> Vector2:
	if player.using_controller:
		return player.get_viewport().get_visible_rect().size * 0.5
	return player.get_viewport().get_mouse_position()
