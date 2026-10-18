extends Node

var clicks := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
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
	print("PASS controller menu navigation")
	get_tree().quit()
