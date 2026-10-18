extends Node

var _direction := 0
var _repeat := 0.0
var _stick_direction := 0
var _pad_direction := 0
var _accept_held := false


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
		if not event.pressed:
			if _accept_held:
				get_viewport().set_input_as_handled()
			_accept_held = false
			return
		if _controls().is_empty():
			return
		get_viewport().set_input_as_handled()
		if not _accept_held:
			_accept_held = true
			_activate()
		return
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y:
		_stick_direction = int(signf(event.axis_value)) if absf(event.axis_value) > 0.55 else 0
	elif event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		var pressed_direction := -1 if event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT] else 1
		if event.pressed:
			_pad_direction = pressed_direction
		elif _pad_direction == pressed_direction:
			_pad_direction = 0
	else:
		return
	var direction := _pad_direction if _pad_direction != 0 else _stick_direction
	if direction == 0:
		_direction = 0
		return
	if _controls().is_empty():
		_direction = 0
		return
	if direction != _direction:
		_step(direction)
		_repeat = 0.35
	_direction = direction
	get_viewport().set_input_as_handled()


func _activate() -> void:
	var controls := _controls()
	if controls.is_empty():
		return
	if get_viewport().gui_get_focus_owner() not in controls:
		controls[0].grab_focus()
	# use native activation so toggles and option menus work too
	for pressed in [true, false]:
		var action := InputEventAction.new()
		action.action = "ui_accept"
		action.pressed = pressed
		get_viewport().push_input(action)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _direction == 0:
		return
	if Input.get_connected_joypads().is_empty():
		_direction = 0
		_stick_direction = 0
		_pad_direction = 0
		return
	_repeat -= delta
	if _repeat <= 0.0:
		_step(_direction)
		_repeat = 0.16


func _controls() -> Array[Control]:
	var result: Array[Control] = []
	var modals := get_tree().get_nodes_in_group("controller_modal")
	for i in range(modals.size() - 1, -1, -1):
		if modals[i].is_visible_in_tree() and not modals[i].is_queued_for_deletion():
			_collect(modals[i], result)
			return result
	for screen in get_tree().get_nodes_in_group("controller_menu"):
		_collect(screen, result)
	return result


func _collect(node: Node, result: Array[Control]) -> void:
	if node.is_queued_for_deletion():
		return
	if node is Control:
		if not node.is_visible_in_tree() or node.modulate.a < 0.1:
			return
		if node.focus_mode == Control.FOCUS_ALL and (node is BaseButton or node is LineEdit):
			if not node is BaseButton or not node.disabled:
				result.append(node)
	for child in node.get_children():
		_collect(child, result)


func _step(direction: int) -> void:
	var controls := _controls()
	if controls.is_empty():
		return
	var index := controls.find(get_viewport().gui_get_focus_owner())
	index = posmod(index + direction, controls.size()) if index >= 0 else (0 if direction > 0 else controls.size() - 1)
	var control := controls[index]
	control.grab_focus()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
