extends Node3D

const MODEL := preload("res://mesh/drone.fbx")
const FOLLOW_HEIGHT := 4.5
const SKY_HEIGHT := 45.0
const FLIGHT_SPEED := 80.0
const FOLLOW_SPEED := 10.0
const ROTOR_MESHES := ["default13", "default14", "default15", "default16"]

var target_peer := 0
var departing := false
var _arriving := true
var _exit_height := 0.0
var _rotors: Array[Node3D] = []


func _ready() -> void:
	var model := MODEL.instantiate()
	_prepare_model(model)
	model.scale = Vector3.ONE * 2.5
	model.position.y = -0.25
	add_child(model)
	visible = not Net.is_spectating()
	var target := _target()
	if target:
		global_position = target.global_position + Vector3.UP * (FOLLOW_HEIGHT + SKY_HEIGHT)
		rotation.y = target.global_rotation.y


func _prepare_model(node: Node) -> void:
	for child in node.get_children():
		# the imported camera must not take over the game view
		if child is Camera3D:
			node.remove_child(child)
			child.free()
			continue
		_prepare_model(child)
		if child is MeshInstance3D and str(child.name) in ROTOR_MESHES:
			var pivot := Node3D.new()
			pivot.position = child.get_aabb().get_center()
			child.owner = null
			node.remove_child(child)
			node.add_child(pivot)
			pivot.add_child(child)
			child.position -= pivot.position
			_rotors.append(pivot)


func set_watched(watched: bool) -> void:
	if watched:
		if departing:
			departing = false
			_arriving = true
	elif not departing:
		departing = true
		_exit_height = global_position.y + SKY_HEIGHT


func _process(delta: float) -> void:
	visible = not Net.is_spectating()
	for i in _rotors.size():
		_rotors[i].rotate_y(delta * TAU * 18.0 * (1.0 if i % 2 == 0 else -1.0))
	if departing:
		global_position.y = move_toward(global_position.y, _exit_height, FLIGHT_SPEED * delta)
		if is_equal_approx(global_position.y, _exit_height):
			queue_free()
		return
	var target := _target()
	if target == null or target._unconscious or not target.is_lifeguard:
		set_watched(false)
		return
	var desired := target.global_position + Vector3.UP * FOLLOW_HEIGHT
	if _arriving:
		global_position = global_position.move_toward(desired, FLIGHT_SPEED * delta)
		_arriving = global_position.distance_squared_to(desired) > 0.01
	else:
		global_position = global_position.lerp(desired, 1.0 - exp(-FOLLOW_SPEED * delta))
	rotation.y = lerp_angle(rotation.y, target.global_rotation.y, 1.0 - exp(-FOLLOW_SPEED * delta))


func _target() -> Node3D:
	var players := get_parent().get_node_or_null("Players")
	return players.get_node_or_null(str(target_peer)) as Node3D if players else null
