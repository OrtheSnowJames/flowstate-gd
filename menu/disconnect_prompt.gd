# small blocking prompt used by online session flow
extends Control

signal closed(confirmed: bool)

@onready var _message: Label = $Panel/VBox/Message
@onready var _button_host: Control = $Panel/VBox/ButtonHost

var _open := false
var _escape_confirms := false


func _ready() -> void:
	visible = false
	set_process_unhandled_input(false)


func open(message: String, confirm_label := "Disconnect", cancel_label := "Cancel") -> bool:
	_open = true
	_escape_confirms = cancel_label.is_empty()
	visible = true
	set_process_unhandled_input(true)
	_message.text = message
	var specs := [{"label": confirm_label, "on_press": func() -> void: _choose(true)}]
	if not cancel_label.is_empty():
		specs.append({"label": cancel_label, "on_press": func() -> void: _choose(false)})
	_button_host.show_buttons(specs)
	var confirmed = await closed
	queue_free()
	return confirmed


func _unhandled_input(event: InputEvent) -> void:
	if _is_escape_pressed(event):
		get_viewport().set_input_as_handled()
		_choose(_escape_confirms)


func _choose(confirmed: bool) -> void:
	if not _open:
		return
	_open = false
	set_process_unhandled_input(false)
	closed.emit(confirmed)


func _is_escape_pressed(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
