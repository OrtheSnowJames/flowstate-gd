# editor time and load time checkboxes for embedding this pool somewhere other than normal
@tool
extends Node3D

@export_group("UI")
# hides doesnt delete the hud as one unit the stamina momentum bars the fps
@export var hide_ui: bool = false:
	set(value):
		hide_ui = value
		_apply_visibility(ui_paths, not value)
@export var ui_paths: Array[NodePath] = [^"gui", ^"FPSLayer", ^"TextureButton"]

@export_group("Water")
# e g so the pool reads as empty drained in the background instead of
@export var delete_water: bool = false:
	set(value):
		delete_water = value
		_apply_deletion(water_path, value)
		_apply_deletion(push_cube_path, value)
@export var water_path: NodePath = ^"water base"
@export var push_cube_path: NodePath = ^"PushCube"

@export_group("Players")
# removes the networked player spawn system outright the players spawn container and its multiplayerspawner
@export var delete_players: bool = false:
	set(value):
		delete_players = value
		_apply_deletion(players_path, value)
		_apply_deletion(spawner_path, value)
@export var players_path: NodePath = ^"Players"
@export var spawner_path: NodePath = ^"MultiplayerSpawner"

const _QUALITY_WATER := {
	"sim_resolution": 384,
	"sim_steps_per_second": 120.0,
	"mesh_resolution": 300,
	"simple_surface": false,
	"refraction_strength": 0.07,
	"detail_strength": 0.18,
	"enable_height_queries": false,
}

const _PERFORMANCE_WATER := {
	"sim_resolution": 192,
	"sim_steps_per_second": 30.0,
	"mesh_resolution": 140,
	"simple_surface": true,
	"refraction_strength": 0.0,
	"detail_strength": 0.05,
	"enable_height_queries": false,
}

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		_apply_performance_mode()


func _ready() -> void:
	# re applies whatevers already true needed because the setters above can fire while this
	_apply_visibility(ui_paths, not hide_ui)
	_apply_deletion(water_path, delete_water)
	_apply_deletion(push_cube_path, delete_water)
	_apply_deletion(players_path, delete_players)
	_apply_deletion(spawner_path, delete_players)
	if not Engine.is_editor_hint():
		_apply_performance_mode()


func _apply_performance_mode() -> void:
	var performance_mode := _performance_mode_enabled()
	var water := get_node_or_null(water_path)
	if water:
		var config := _PERFORMANCE_WATER if performance_mode else _QUALITY_WATER
		for key in config:
			water.set(key, config[key])

	var world_environment := get_node_or_null("WorldEnvironment")
	if world_environment and world_environment.environment:
		world_environment.environment.glow_enabled = not performance_mode


func _performance_mode_enabled() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return bool(settings.get("performance_mode")) if settings else false

func _apply_visibility(paths: Array[NodePath], to_visible: bool) -> void:
	if not is_inside_tree():
		return
	for path in paths:
		var n := get_node_or_null(path)
		if n:
			n.visible = to_visible

func _apply_deletion(path: NodePath, should_delete: bool) -> void:
	if not should_delete or not is_inside_tree():
		return
	var n := get_node_or_null(path)
	if n:
		n.queue_free()
