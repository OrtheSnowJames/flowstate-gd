@tool
extends Label

@export_tool_button("Center Pivot")
var center_pivot_button = center_pivot

func _ready() -> void:
	if not Engine.is_editor_hint():
		item_rect_changed.connect(center_pivot)

	center_pivot()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_TRANSFORM_CHANGED:
		center_pivot()

func center_pivot() -> void:
	pivot_offset = size / 2.0
