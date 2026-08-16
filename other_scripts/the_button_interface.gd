@tool
extends Node

@export var button_text: String = "":
	set(value):
		button_text = value
		if not is_inside_tree():
			return
			
		_update_child_node()

func _update_child_node() -> void:
	if has_node("LabelSpace/Label"):
		$LabelSpace/Label.text = button_text
