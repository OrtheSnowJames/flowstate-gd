## The "[R] Revive" tag that floats over a downed teammate a lifeguard is
## standing close enough to pick up.
##
## Built out of Control nodes in a CanvasLayer rather than a Sprite3D/Label3D
## billboard in the world. That's what "flat, but on top of the player" gets
## you literally: screen-space, so it never picks up perspective skew or
## foreshortening as the camera swings, never clips into water or geometry,
## and the keycap stays pixel-crisp at any distance. It follows the target by
## unprojecting that body's world position every frame (see _process), so it
## still reads as belonging to that specific player rather than being HUD.
##
## Owned by the local player (see player.gd's _ready), which hands it a target
## each frame -- one prompt exists per window no matter how many bodies are
## down, because only ever one of them is the one you'd pick up.
extends Control

## Metres above the target's origin to sit, so the tag floats over the head
## instead of inside the chest. The capsule is ~2m tall and its origin is at
## the middle, so a bit over half its height clears it.
const _WORLD_OFFSET := Vector3(0.0, 1.5, 0.0)

const _BOX_COLOR := Color(0.1, 0.1, 0.12, 0.62)
const _KEYCAP_FACE := Color(0.88, 0.88, 0.9, 0.95)
const _KEYCAP_TEXT := Color(0.08, 0.08, 0.1, 1.0)
const _LABEL_TEXT := Color(1.0, 1.0, 1.0, 0.95)

## Fade in/out time. Short enough to feel responsive when you swim into range,
## long enough that bobbing right on the edge of revive_range doesn't strobe.
const _FADE_TIME := 0.12

var _target: Node3D = null
var _camera: Camera3D = null
var _fade: Tween

@onready var _box: PanelContainer = $Box


func _ready() -> void:
	# Nothing here should ever eat a click -- it's a floating label, and the
	# menu/HUD underneath has to stay reachable. MOUSE_FILTER_IGNORE on the
	# root isn't inherited, so the children set it for themselves too (see
	# revive_prompt.tscn).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false


## Called every frame by the local player with whichever body it could revive
## right now, or null. Idempotent: passing the same target repeatedly just
## keeps the prompt up, and passing null takes it down.
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
		# Hide outright once faded, so a fully transparent prompt isn't still
		# being laid out and drawn every frame for nothing.
		_fade.tween_callback(func() -> void: visible = false)


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _camera == null:
		return
	var world := _target.global_position + _WORLD_OFFSET
	# Behind the camera: unproject_position() has no meaningful answer there
	# and would happily place the tag somewhere on screen anyway, so a downed
	# teammate behind you would sprout a prompt in front of you.
	if _camera.is_position_behind(world):
		_box.visible = false
		return
	_box.visible = true
	var screen := _camera.unproject_position(world)
	# Centred horizontally on the body, sitting just above the offset point.
	_box.position = screen - Vector2(_box.size.x * 0.5, _box.size.y)
