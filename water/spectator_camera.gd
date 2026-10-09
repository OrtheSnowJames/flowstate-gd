# spectator camera follows living lifeguards then falls back to the pool drone view
extends Camera3D

const _POOL_CENTER := Vector3(0.0, 4.0, 0.0)
const _DRONE_POS := Vector3(-30.0, 34.0, 20.0)
const _TARGET_HEIGHT := Vector3.UP * 1.5
const _FOLLOW_HEIGHT := Vector3.UP * 5.0
const _FOLLOW_DISTANCE := 8.0
const _FOLLOW_SPEED := 5.0
const _DRONE_SPEED := 3.0


func _ready() -> void:
	fov = 68.0
	near = 0.05
	far = 220.0
	global_position = _DRONE_POS
	look_at(_POOL_CENTER, Vector3.UP)
	current = true


func _process(delta: float) -> void:
	var target := _living_lifeguard()
	Net.set_spectator_target(str(target.name).to_int() if target else 0)
	if target:
		_follow(target, delta)
	else:
		_drone(delta)


func _living_lifeguard() -> Node3D:
	return Net.living_lifeguard()


func _follow(target: Node3D, delta: float) -> void:
	var behind := target.global_transform.basis.z * _FOLLOW_DISTANCE
	var desired := target.global_position + behind + _FOLLOW_HEIGHT
	global_position = global_position.lerp(desired, 1.0 - exp(-_FOLLOW_SPEED * delta))
	_look_at_target(target.global_position + _TARGET_HEIGHT)


func _drone(delta: float) -> void:
	global_position = global_position.lerp(_DRONE_POS, 1.0 - exp(-_DRONE_SPEED * delta))
	_look_at_target(_POOL_CENTER)


func _look_at_target(target_position: Vector3) -> void:
	if Input.is_action_pressed("look_scoreboard") and not Net.input_blocked_by_menu():
		var scene := get_tree().current_scene
		var scoreboard := scene.get_node_or_null("Scoreboard") if scene else null
		if scoreboard is Node3D:
			var title := scoreboard.get_node_or_null("SCORE")
			target_position = title.global_position if title is Node3D else scoreboard.global_position
	look_at(target_position, Vector3.UP)
