extends Control

const WORLD_OFFSET := Vector3(0.0, 2.5, 0.0)

@onready var _box: PanelContainer = $Box
@onready var _action: Label = $Box/Row/Action


func _ready() -> void:
	hide()


func show_for(player: Node3D, camera: Camera3D, action: String) -> void:
	if action.is_empty() or not is_instance_valid(player) or not is_instance_valid(camera):
		hide()
		return
	var world := player.get_global_transform_interpolated().origin + WORLD_OFFSET
	if camera.is_position_behind(world):
		hide()
		return
	_action.text = action
	_box.reset_size()
	var screen := get_global_transform_with_canvas().affine_inverse() * VR.project_ui_position(world, camera)
	_box.position = screen - Vector2(_box.size.x * 0.5, _box.size.y)
	var margin := Vector2(8, 8)
	_box.position = _box.position.clamp(margin, (size - _box.size - margin).max(margin))
	show()
