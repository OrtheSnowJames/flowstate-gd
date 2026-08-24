@tool
extends Control

## A settings row: a static name on the left ("Camera Height") and an
## amount with a left/right arrow pair on the right ("< 3.2m >") -- right
## arrow increments, left arrow decrements. Unlike the_button.tscn (one
## clickable node with one `pressed` signal), this wraps three interactive
## children, so it exposes two signals instead and menu_screen.gd wires each
## to its own callback. Declared `extends Control` (not `extends Node` like
## the_button_interface.gd) specifically so `self` is already statically a
## Control here -- no get_parent()/self typing workaround needed, since this
## script is only ever meant to sit on a Control-rooted scene.

signal left_pressed
signal right_pressed

@export var row_label: String = "":
	set(value):
		row_label = value
		if is_inside_tree():
			_update_labels()

@export var amount_text: String = "":
	set(value):
		amount_text = value
		if is_inside_tree():
			_update_labels()


func _ready() -> void:
	_update_labels()
	$LeftArrow.pressed.connect(func() -> void: left_pressed.emit())
	$RightArrow.pressed.connect(func() -> void: right_pressed.emit())


func _update_labels() -> void:
	if has_node("RowLabel"):
		$RowLabel.text = row_label
	if has_node("AmountLabel"):
		$AmountLabel.text = amount_text
