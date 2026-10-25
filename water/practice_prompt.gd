extends "res://water/revive_prompt.gd"


func _ready() -> void:
	super._ready()
	var keycap := $Box/Row/Keycap.duplicate()
	keycap.get_node("Key").text = "D"
	$Box/Row.add_child(keycap)
	var action := $Box/Row/Action.duplicate()
	action.text = "Delete"
	$Box/Row.add_child(action)


func show_for(target: Node3D, camera: Camera3D, using_controller := false) -> void:
	super.show_for(target, camera, using_controller)
	$Box/Row/Keycap/Key.text = "E"
	$Box/Row/Action.text = "Edit"


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(_target) or not is_instance_valid(_camera):
		return
	var screen := _camera.unproject_position(_target.global_position + Vector3.UP * 2.5)
	_box.position = screen - Vector2(_box.size.x * 0.5, _box.size.y)
	var viewport_size := get_viewport_rect().size
	_box.position = _box.position.clamp(Vector2(8, 8), (viewport_size - _box.size - Vector2(8, 8)).max(Vector2(8, 8)))
