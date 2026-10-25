extends Node3D

const BOT := preload("res://water/practice_bot.gd")
const PROMPT := preload("res://water/practice_prompt.tscn")
const EDITOR := preload("res://menu/practice_editor.tscn")
const NAMES := ["her majesty", "john", "john pork", "big fern", "eli from the nut", "eli (evil)", "bob42", "jhev", "moscow", "asd"]

var _next_name := 0
var _hovered: Node3D
var _prompt: Control
var _editor: Control
var _human: Node3D
var _layer: CanvasLayer


func _ready() -> void:
	process_priority = -10
	_layer = CanvasLayer.new()
	_layer.layer = 15
	add_child(_layer)
	_prompt = PROMPT.instantiate()
	_layer.add_child(_prompt)


func available() -> bool:
	return OS.get_name() in ["Windows", "macOS", "Linux"] and not VR.active and not Net.is_online() \
		and Net.round_state == Net.RoundState.PLAYING and not Net._round_over and not Net.is_spectating()


func _local_player() -> Node3D:
	var players := Net._players_root()
	return players.get_node_or_null(str(multiplayer.get_unique_id())) if players else null


func _process(_delta: float) -> void:
	_human = _local_player()
	if not is_instance_valid(_human):
		return
	var editing := available() and Input.is_physical_key_pressed(KEY_CTRL)
	_human.practice_input_blocked = editing or is_instance_valid(_editor)
	if not available() and is_instance_valid(_editor):
		_editor.queue_free()
	if editing and not is_instance_valid(_editor) and not Net.input_blocked_by_menu():
		_hovered = _pick_player()
	else:
		_hovered = null
	_prompt.show_for(_hovered, _human._camera)


func _input(event: InputEvent) -> void:
	if not available() or Net.input_blocked_by_menu() or not (event is InputEventKey):
		return
	if not event.pressed or event.echo or not event.ctrl_pressed:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if key not in [KEY_C, KEY_E, KEY_D]:
		return
	get_viewport().set_input_as_handled()
	_human = _local_player()
	if not is_instance_valid(_human) or _human._unconscious or _human.movement_locked:
		return
	_human.practice_input_blocked = true
	if key == KEY_C:
		spawn_player()
		return
	_hovered = _pick_player()
	if not is_instance_valid(_hovered):
		return
	if key == KEY_E:
		edit_player(_hovered)
	else:
		delete_player(_hovered)


func spawn_player() -> Node3D:
	var human := _local_player()
	if not available() or human == null or human._unconscious or human.movement_locked:
		return null
	var body = Net.PLAYER_SCENE.instantiate()
	var brain := BOT.new()
	brain.name = "PracticeController"
	brain.display_name = NAMES[_next_name % NAMES.size()]
	if _next_name >= NAMES.size():
		brain.display_name += " %d" % (1 + _next_name / NAMES.size())
	_next_name += 1
	body.name = "PracticePlayer%d" % _next_name
	body.practice = brain
	body.take_over_camera = false
	body.team = human.team
	body.ocean_path = human._ocean.get_path()
	body.add_child(brain)
	body.transform = global_transform.affine_inverse() * human.global_transform
	for other in get_tree().get_nodes_in_group("player"):
		if body.position.distance_to(to_local(other.global_position)) < 2.1:
			brain.allow_spawn_overlap(other)
	add_child(body)
	body.reset_physics_interpolation()
	return body


func _pick_player() -> Node3D:
	if not is_instance_valid(_human) or not is_instance_valid(_human._camera):
		return null
	var camera: Camera3D = _human._camera
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(mouse) * 150.0,
		1, [_human.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var body = hit.get("collider")
	return body if is_instance_valid(body) and body.get_parent() == self and not body.is_queued_for_deletion() else null


func edit_player(body: Node3D) -> void:
	if not available() or not is_instance_valid(body) or body.get_parent() != self or is_instance_valid(_editor):
		return
	_editor = EDITOR.instantiate()
	_editor.target = body
	_layer.add_child(_editor)
	_hovered = null
	_prompt.show_for(null, _human._camera)


func delete_player(body: Node3D) -> void:
	if not available() or not is_instance_valid(body) or body.get_parent() != self:
		return
	body._cast_water_wall_stop()
	body.queue_free()
	_hovered = null
	_prompt.show_for(null, _human._camera)


func _exit_tree() -> void:
	if is_instance_valid(_human):
		_human.practice_input_blocked = false
