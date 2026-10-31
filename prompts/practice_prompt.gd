extends Control

const WORLD_OFFSET := Vector3(0.0, 2.5, 0.0)
const FADE_TIME := 0.12

var _target: Node3D
var _camera: Camera3D
var _fade: Tween

@onready var _content: VBoxContainer = $VBoxContainer
@onready var _hp: ProgressBar = $VBoxContainer/HP


func _ready() -> void:
	modulate.a = 0.0
	hide()


func show_for(target: Node3D, camera: Camera3D) -> void:
	_camera = camera
	var next_target: Node3D = target if is_instance_valid(target) and is_instance_valid(camera) else null
	if next_target == _target:
		return
	_target = next_target
	_set_shown(_target != null)
	if _target != null:
		_update_content()


func _set_shown(shown: bool) -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	if shown:
		show()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0 if shown else 0.0, FADE_TIME)
	if not shown:
		_fade.tween_callback(hide)


func _process(_delta: float) -> void:
	if _target == null:
		return
	if not is_instance_valid(_target) or not is_instance_valid(_camera):
		show_for(null, null)
		return
	_update_content()


func _update_content() -> void:
	_hp.max_value = _target.max_stamina_per_mode(Net.game_mode)
	_hp.value = _target.stamina
	var world := _target.global_position + WORLD_OFFSET
	_content.visible = not _camera.is_position_behind(world)
	if not _content.visible:
		return
	_content.reset_size()
	var screen := get_global_transform_with_canvas().affine_inverse() * _camera.unproject_position(world)
	_content.position = screen - Vector2(_content.size.x * 0.5, _content.size.y)
	var margin := Vector2(8, 8)
	_content.position = _content.position.clamp(margin, (size - _content.size - margin).max(margin))
