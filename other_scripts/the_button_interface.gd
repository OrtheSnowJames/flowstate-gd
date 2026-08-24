@tool
extends Node

## Longer labels (e.g. "Connect to Localhost") don't fit the button's
## original fixed 320px width -- rather than a 9-slice (no vertical caps are
## needed, the art is only ever one row tall), the_button.tscn's background
## is a NinePatchRect sliced left/middle/right only (patch_margin_top/bottom
## left at 0), anchored to fill the root TextureButton's rect. So growing the
## root button's own size is all it takes for the background to stretch to
## match -- this script just has to measure the label text and set that size.
@export var button_text: String = "":
	set(value):
		button_text = value
		if not is_inside_tree():
			return

		_update_child_node()

## Space reserved on the left for the arrow icon + gap (matches LabelSpace's
## offset_left in the_button.tscn) and breathing room on the right past the
## text before the right cap starts.
const _LEFT_PAD := 100.0
const _RIGHT_PAD := 40.0
## Never shrink below the original button width, even for short labels.
const _MIN_WIDTH := 320.0
const _HEIGHT := 100.0

func _update_child_node() -> void:
	if not has_node("LabelSpace/Label"):
		return
	var label: Label = $LabelSpace/Label
	label.text = button_text

	# This script is attached directly to the root TextureButton (see
	# the_button.tscn) -- unlike button_size_changer.gd, which lives on a
	# separate child node and needs get_parent() to reach the button, here
	# `self` already *is* the button. get_parent() would instead return
	# whatever node this button instance gets added to (e.g. menu_screen.gd's
	# Control), silently resizing the wrong node.
	# Untyped on purpose: this script declares `extends Node` (so it can also
	# run as a @tool script without pulling in the full Control/TextureButton
	# API), so `self` is statically typed as Node -- assigning it to a
	# `var button: Control` fails to compile even though the actual attached
	# node is always a TextureButton at runtime. Same pitfall as
	# button_size_changer.gd's my_button typing.
	var button = self
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(button_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := maxf(_MIN_WIDTH, _LEFT_PAD + text_width + _RIGHT_PAD)
	button.size = Vector2(width, _HEIGHT)
	# Keep the hover/click scale tween (button_size_changer.gd) growing from
	# the button's true center instead of drifting back to the top-left
	# default every time the width changes.
	button.pivot_offset = button.size / 2.0
