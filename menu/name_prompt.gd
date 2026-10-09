# reusable name entry modal a translucent full screen backdrop blocks input to whatevers behind
extends Control

@onready var _title_label: Label = $Backdrop/Panel/VBox/Title
@onready var _line_edit: LineEdit = $Backdrop/Panel/VBox/LineEdit
@onready var _button_host: Control = $Backdrop/Panel/VBox/ButtonHost

var _on_submit: Callable
var _on_cancel: Callable


# shows the prompt pre filled with initial_text titled title calls on_submit new_text with non
func open(initial_text: String, title: String, on_submit: Callable,
		on_cancel: Callable = Callable()) -> void:
	_title_label.text = title
	_line_edit.text = initial_text
	_on_submit = on_submit
	_on_cancel = on_cancel

	var specs := [{"label": "Confirm", "on_press": _submit}]
	if on_cancel.is_valid():
		specs.append({"label": "Cancel", "on_press": _cancel})
	_button_host.show_buttons(specs)

	if not _line_edit.text_submitted.is_connected(_on_line_submitted):
		_line_edit.text_submitted.connect(_on_line_submitted)

	# one frame so the lineedit genuinely exists in the tree before asking it to
	await get_tree().process_frame
	_line_edit.grab_focus()
	_line_edit.caret_column = _line_edit.text.length()


func _on_line_submitted(_text: String) -> void:
	_submit()


func _submit() -> void:
	var text := _line_edit.text.strip_edges()
	if text.is_empty():
		_flash_empty()
		return
	if _on_submit.is_valid():
		_on_submit.call(text)
	queue_free()


func _cancel() -> void:
	if _on_cancel.is_valid():
		_on_cancel.call()
	queue_free()


var _flash_tween: Tween

# a blank confirm doesnt close the prompt an empty name isnt legal net gds
func _flash_empty() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_line_edit.modulate = Color(1.0, 0.5, 0.5)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_line_edit, "modulate", Color.WHITE, 0.3)
