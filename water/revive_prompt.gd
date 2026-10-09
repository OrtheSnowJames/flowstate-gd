# the r revive tag that floats over a downed teammate a lifeguard is standing
extends Control

# metres above the targets origin to sit so the tag floats over the head
const _WORLD_OFFSET := Vector3(0.0, 1.5, 0.0)

const _BOX_COLOR := Color(0.1, 0.1, 0.12, 0.62)
const _KEYCAP_FACE := Color(0.88, 0.88, 0.9, 0.95)
const _KEYCAP_TEXT := Color(0.08, 0.08, 0.1, 1.0)
const _LABEL_TEXT := Color(1.0, 1.0, 1.0, 0.95)

# fade in out time short enough to feel responsive when you swim into range
const _FADE_TIME := 0.12

var _target: Node3D = null
var _camera: Camera3D = null
var _fade: Tween

@onready var _box: PanelContainer = $Box


func _ready() -> void:
	# nothing here should ever eat a click its a floating label and the menu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false


# called every frame by the local player with whichever body it could revive right
func show_for(target: Node3D, camera: Camera3D) -> void:
	_camera = camera
	if target == _target:
		return
	_target = target
	_set_shown(target != null)


func _set_shown(shown: bool) -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	if shown:
		visible = true
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0 if shown else 0.0, _FADE_TIME)
	if not shown:
		# hide outright once faded so a fully transparent prompt isnt still being laid out
		_fade.tween_callback(func() -> void: visible = false)


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _camera == null:
		return
	var world := _target.global_position + _WORLD_OFFSET
	# behind the camera unproject_position has no meaningful answer there and would happily place the
	if _camera.is_position_behind(world):
		_box.visible = false
		return
	_box.visible = true
	var screen := _camera.unproject_position(world)
	# centred horizontally on the body sitting just above the offset point
	_box.position = screen - Vector2(_box.size.x * 0.5, _box.size.y)
