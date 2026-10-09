@tool
extends Node

# longer labels e g connect to localhost dont fit the buttons original fixed 320px
@export var button_text: String = "":
	set(value):
		button_text = value
		if not is_inside_tree():
			return

		_update_child_node()

# space reserved on the left for the arrow icon gap matches labelspaces offset_left in
const _LEFT_PAD := 100.0
const _RIGHT_PAD := 40.0
# never shrink below the original button width even for short labels
const _MIN_WIDTH := 320.0
const _HEIGHT := 100.0

func _update_child_node() -> void:
	if not has_node("LabelSpace/Label"):
		return
	var label: Label = $LabelSpace/Label
	label.text = button_text

	# this script is attached directly to the root texturebutton see the_button tscn unlike button_size_changer
	var button = self
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(button_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := maxf(_MIN_WIDTH, _LEFT_PAD + text_width + _RIGHT_PAD)
	button.size = Vector2(width, _HEIGHT)
	# keep the hover click scale tween button_size_changer gd growing from the buttons true center
	button.pivot_offset = button.size / 2.0
