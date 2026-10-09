# floating name tag over a teammates head player gd keeps one of these per
extends Control

const _WORLD_OFFSET := Vector3(0.0, 1.7, 0.0)

var target: Node3D = null
var _camera: Camera3D = null

@onready var _box: PanelContainer = $Box
@onready var _label: Label = $Box/Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# set once at creation display_name is passed in rather than read off net name_of
func setup(new_target: Node3D, camera: Camera3D, display_name: String) -> void:
	target = new_target
	_camera = camera
	_label.text = display_name


func _process(_delta: float) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree() \
			or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		_box.visible = false
		return
	var world := target.global_position + _WORLD_OFFSET
	# behind the camera unproject_position has no meaningful answer there and would happily place the
	if _camera.is_position_behind(world):
		_box.visible = false
		return
	_box.visible = true
	var screen := _camera.unproject_position(world)
	_box.position = screen - Vector2(_box.size.x * 0.5, _box.size.y)
