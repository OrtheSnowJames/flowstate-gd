@tool
extends Control

# a settings row a static name on the left camera height and an amount

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
