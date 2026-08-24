## Editor-time (and load-time) checkboxes for embedding this pool somewhere
## other than normal gameplay -- the menu background is why this exists (see
## menu/menu.tscn, which instances ocean1.tscn purely for the geometry,
## lighting, grass and bathroom, and wants none of the gameplay HUD, water, or
## networked-player system that come along for the ride otherwise).
##
## Every toggle is a (bool, NodePath) pair: the checkbox does the thing, the
## path says WHAT it does it to -- so retargeting a toggle to a differently
## named node doesn't need a code change, just a different path in the
## Inspector. All default to false/off, so leaving this script attached and
## untouched changes nothing about normal gameplay.
##
## These are exported properties, not direct edits to the scene tree, so they
## work correctly on an INSTANCE of this scene (e.g. "ocean_scene" in
## menu.tscn) without needing "Editable Children" mode at all: every time the
## scene loads, Godot instantiates ocean1.tscn fresh (water/gui/Players all
## present, same as always) and then applies that instance's property
## overrides -- which re-fires these setters and re-applies whichever toggles
## are on. Deterministic every load, and toggling one on this script directly
## on ocean1.tscn's own root would strip real gameplay of its own UI/water/
## players -- almost certainly not what you want; toggle it on an INSTANCE.
##
## Deletion is real: queue_free(), not just hidden. If you might want the node
## back, use hide_ui (visibility, reversible) rather than one of the delete_*
## switches -- there's no undo for those once the scene's saved with one on.
@tool
extends Node3D

@export_group("UI")
## Hides (doesn't delete) the HUD as one unit: the stamina/momentum bars, the
## FPS counter, and a leftover empty debug button. Bundled rather than
## separate switches because every use of this so far has wanted either all
## of the gameplay UI or none of it.
@export var hide_ui: bool = false:
	set(value):
		hide_ui = value
		_apply_visibility(ui_paths, not value)
@export var ui_paths: Array[NodePath] = [^"gui", ^"FPSLayer", ^"TextureButton"]

@export_group("Water")
## E.g. so the pool reads as empty/drained in the background instead of just
## having its water invisible. Takes PushCube with it, not just "water base"
## itself -- PushCube's Buoyancy component caches a reference to the water
## node in its own _ready() and calls get_height_at() on it every physics
## tick, so deleting the water out from under a still-alive PushCube left a
## dangling reference erroring every frame. A cube with no water to float in
## has no reason to still be there anyway.
@export var delete_water: bool = false:
	set(value):
		delete_water = value
		_apply_deletion(water_path, value)
		_apply_deletion(push_cube_path, value)
@export var water_path: NodePath = ^"water base"
@export var push_cube_path: NodePath = ^"PushCube"

@export_group("Players")
## Removes the networked-player spawn system outright (the "Players" spawn
## container and its MultiplayerSpawner) -- not one player's camera, ALL of
## them, permanently, for scenes that should never have any player spawn into
## them at all. For a scene that still wants exactly one hand-placed,
## controllable player without it grabbing the camera or writing the HUD, use
## player.gd's own take_over_camera export instead (see water/player.gd) --
## that's a single player choosing not to take over, not the whole system
## being gone.
@export var delete_players: bool = false:
	set(value):
		delete_players = value
		_apply_deletion(players_path, value)
		_apply_deletion(spawner_path, value)
@export var players_path: NodePath = ^"Players"
@export var spawner_path: NodePath = ^"MultiplayerSpawner"

func _ready() -> void:
	# Re-applies whatever's already true. Needed because the setters above can
	# fire while this node is still being deserialized, before it (or the
	# nodes its paths point at) are actually in the tree -- get_node_or_null
	# would find nothing yet, so the toggle would silently do nothing at load
	# time despite being checked. This is the pass that's guaranteed to run
	# with the whole subtree present, load or live-editor-toggle alike.
	_apply_visibility(ui_paths, not hide_ui)
	_apply_deletion(water_path, delete_water)
	_apply_deletion(push_cube_path, delete_water)
	_apply_deletion(players_path, delete_players)
	_apply_deletion(spawner_path, delete_players)

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
