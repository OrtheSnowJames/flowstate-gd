extends Node

const MESSAGE := preload("res://menu/appear_disappear_text.tscn")
const XR_STATUS := "OpenXR unavailable. Launch with --xr-mode on and your VR runtime running."
var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(1))
	get_tree().root.content_scale_size = Vector2i.ZERO
	var background := ColorRect.new()
	background.color = Color(0.08, 0.11, 0.1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var message := MESSAGE.instantiate()
	add_child(message)
	for dimensions in [Vector2i(1152, 648), Vector2i(1920, 1080), Vector2i(640, 360), Vector2i(320, 240), Vector2i(360, 640)]:
		get_tree().root.size = dimensions
		await _frames()
		for verdict in ["YOU WIN", "GET BETTER", "3"]:
			message.play(verdict)
			await _frames()
			_check_bounds(message._label, verdict)
			_capture("%dx%d-%s" % [dimensions.x, dimensions.y, verdict.to_lower().replace(" ", "-")])
			while message._tween.is_running():
				_check_bounds(message._label, verdict + " animation")
				await get_tree().process_frame
		await Transition.show_status(XR_STATUS)
		await _frames()
		_check_bounds(Transition._status_label, "openxr status")
		_expect(Transition._status_label.get_line_count() > 1 or dimensions.x >= 1152, "status wraps on narrow screens")
		_capture("%dx%d-openxr" % [dimensions.x, dimensions.y])
		await Transition.hide_status()
	message.play("GET BETTER")
	get_tree().root.size = Vector2i(640, 360)
	await _frames()
	_check_bounds(message._label, "resized banner")
	print("FAIL message layout" if failed else "PASS message layout")
	get_tree().quit(1 if failed else 0)


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _check_bounds(label: Label, description: String) -> void:
	var viewport := get_viewport().get_visible_rect().grow(-1.0)
	var transform := label.get_global_transform_with_canvas()
	for corner in [Vector2.ZERO, Vector2(label.size.x, 0), label.size, Vector2(0, label.size.y)]:
		_expect(viewport.has_point(transform * corner), description + " stays inside the screen")


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("/tmp/flowstate-message-" + name + ".png")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + description)
