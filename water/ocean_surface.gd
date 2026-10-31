extends RefCounted

const MATERIAL := preload("res://water/water shader.tres")

var material: ShaderMaterial = MATERIAL.duplicate()
var _positions := PackedVector3Array()
var _ages := PackedFloat32Array()
var _cursor := 0
var _elapsed := 0.0


func _init() -> void:
	_positions.resize(128)
	_positions.fill(Vector3(99999, 0, 99999))
	_ages.resize(128)
	_ages.fill(9999.0)
	update(0.0)


func add_ripple(pos: Vector3) -> void:
	_positions[_cursor] = pos
	_ages[_cursor] = 0.0
	# the ocean shader samples every second trail slot
	_cursor = (_cursor + 2) % int(material.get_shader_parameter("trail_count"))


func track_bodies(states: Dictionary, surface_y: float) -> void:
	for state in states.values():
		var body = state.body
		if not is_instance_valid(body):
			continue
		var pos: Vector3 = body.global_position
		if absf(pos.y - surface_y) < state.r * 2.0 and pos.distance_to(state.wake_pos) >= 0.08:
			add_ripple(pos)
			state.wake_pos = pos


func update(delta: float) -> void:
	_elapsed += delta
	for i in int(material.get_shader_parameter("trail_count")):
		_ages[i] += delta
	material.set_shader_parameter("wave_time", _elapsed)
	material.set_shader_parameter("trail_pos", _positions)
	material.set_shader_parameter("trail_age", _ages)
