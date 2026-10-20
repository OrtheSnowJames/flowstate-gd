extends Node

var clicks := 0
var escapes := 0


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		escapes += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	assert(start.is_action_pressed("ui_cancel"))
	assert(Net._is_escape_pressed(start))
	assert(not VR._update_escape_chord(true, false, 1.0))
	assert(escapes == 0)
	assert(VR._update_escape_chord(true, true, 0.3))
	assert(escapes == 0)
	VR._update_escape_chord(true, true, 0.31)
	Input.flush_buffered_events()
	assert(escapes == 1)
	VR._update_escape_chord(true, true, 2.0)
	assert(escapes == 1)
	assert(VR._update_escape_chord(false, true, 0.1))
	VR._update_escape_chord(true, true, 1.0)
	assert(escapes == 1)
	assert(not VR._update_escape_chord(false, false, 0.1))
	VR._update_escape_chord(true, true, 0.61)
	Input.flush_buffered_events()
	assert(escapes == 2)
	VR._update_escape_chord(false, false, 0.1)
	var menu := Control.new()
	add_child(menu)
	menu.add_to_group("controller_menu")
	var buttons: Array[Button] = []
	for i in range(3):
		var button := Button.new()
		menu.add_child(button)
		buttons.append(button)
	ControllerNavigation._step(1)
	assert(buttons[0].has_focus())
	buttons[0].pressed.connect(func(): clicks += 1)
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	ControllerNavigation._input(accept)
	assert(clicks == 1)
	ControllerNavigation._input(accept)
	assert(clicks == 1)
	accept.pressed = false
	ControllerNavigation._input(accept)
	assert(clicks == 1)
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	ControllerNavigation._input(down)
	assert(buttons[1].has_focus())
	down.pressed = false
	ControllerNavigation._input(down)
	assert(ControllerNavigation._direction == 0)
	ControllerNavigation._step(-1)
	ControllerNavigation._step(1)
	assert(buttons[1].has_focus())
	buttons[2].disabled = true
	ControllerNavigation._step(1)
	assert(buttons[0].has_focus())
	ControllerNavigation._step(-1)
	assert(buttons[1].has_focus())
	var modal := Control.new()
	add_child(modal)
	modal.add_to_group("controller_modal")
	var confirm := Button.new()
	modal.add_child(confirm)
	ControllerNavigation._step(1)
	assert(confirm.has_focus())
	ControllerNavigation._step(1)
	assert(confirm.has_focus())
	modal.hide()
	ControllerNavigation._step(1)
	assert(buttons[0].has_focus())
	var field := LineEdit.new()
	menu.add_child(field)
	field.grab_focus()
	field.unedit()
	assert(not field.is_editing())
	ControllerNavigation._activate()
	assert(field.is_editing())
	assert(field.virtual_keyboard_enabled and field.virtual_keyboard_show_on_focus)
	print("PASS controller menu navigation")
	get_tree().quit()
