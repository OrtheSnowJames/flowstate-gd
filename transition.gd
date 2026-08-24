## Full-screen overlay for menu transitions and connection status -- a blur
## (menu/blur_overlay.gdshader), a solid fade-to-black, and a status label,
## all owned by one CanvasLayer that IS this autoload (added straight to
## /root the moment the game boots, same as Net), so it survives every
## change_scene_to_file() automatically instead of needing to be re-added per
## scene.
##
## Every public method kills-and-recreates its own Tween and reads the
## CURRENT value as that tween's starting point -- same idiom water/player.gd
## already uses for the eyelid close/open tweens -- so calling blur_in()
## while blur_out() is still running (or vice versa) reverses smoothly
## instead of the two fighting over the same parameter.
extends CanvasLayer

const _BLUR_SHADER := preload("res://menu/blur_overlay.gdshader")

const _BLUR_DURATION := 0.35
const _FADE_DURATION := 0.4
const _STATUS_DURATION := 0.25

var _blur_rect: ColorRect
var _blur_mat: ShaderMaterial
var _fade_rect: ColorRect
var _status_label: Label

var _blur_tween: Tween
var _fade_tween: Tween
var _status_tween: Tween


func _ready() -> void:
	# Above everything else drawn in any scene, including that scene's own
	# CanvasLayers (default layer 1, same as e.g. water/ocean1.tscn's "gui").
	layer = 100

	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = _BLUR_SHADER
	# Explicit, not relying on the shader's own declared default -- whether
	# get_shader_parameter() resolves an never-set parameter to that default
	# or returns null is more than I want to bet a typed `float` assignment
	# on in _tween_blur() below.
	_blur_mat.set_shader_parameter("amount", 0.0)
	_blur_rect = _make_full_rect()
	_blur_rect.material = _blur_mat
	add_child(_blur_rect)

	_fade_rect = _make_full_rect()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	add_child(_fade_rect)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_CENTER)
	_status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 32)
	_status_label.modulate.a = 0.0
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_label)


## Fully transparent, but still a real Control rect sitting on top of every
## other CanvasLayer -- MOUSE_FILTER_IGNORE is load-bearing, not tidiness:
## without it this would swallow every click in the game the instant it's
## added, blur/fade visible or not, since Controls intercept input by rect,
## not by how transparent they currently look.
func _make_full_rect() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Brings the blur+darken in. Awaitable -- resolves once the tween finishes,
## so callers can `await Transition.blur_in()` before doing whatever needs to
## happen while the screen is obscured.
func blur_in() -> void:
	await _tween_blur(1.0)


## Same, in reverse.
func blur_out() -> void:
	await _tween_blur(0.0)


func _tween_blur(target: float) -> void:
	if _blur_tween and _blur_tween.is_valid():
		_blur_tween.kill()
	var from: float = _blur_mat.get_shader_parameter("amount")
	_blur_tween = create_tween()
	_blur_tween.tween_method(
		func(v: float) -> void: _blur_mat.set_shader_parameter("amount", v),
		from, target, _BLUR_DURATION)
	await _blur_tween.finished


## Fades the whole screen to solid black. Awaitable -- the intended use is
## `await Transition.fade_to_black()` before change_scene_to_file()/spawning
## a player/etc., so the swap happens while the screen is actually covered,
## not mid-fade.
func fade_to_black() -> void:
	await _tween_fade(1.0)


func fade_from_black() -> void:
	await _tween_fade(0.0)


func _tween_fade(target: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	var from := _fade_rect.color.a
	_fade_tween = create_tween()
	_fade_tween.tween_method(
		func(v: float) -> void: _fade_rect.color.a = v,
		from, target, _FADE_DURATION)
	await _fade_tween.finished


## Status text (e.g. "Connecting..."), faded independently of the blur/fade
## above so a caller can update the message (or clear it) without
## retriggering the whole overlay.
func show_status(text: String) -> void:
	_status_label.text = text
	await _tween_status(1.0)


func hide_status() -> void:
	await _tween_status(0.0)


func _tween_status(target: float) -> void:
	if _status_tween and _status_tween.is_valid():
		_status_tween.kill()
	var from := _status_label.modulate.a
	_status_tween = create_tween()
	_status_tween.tween_method(
		func(v: float) -> void: _status_label.modulate.a = v,
		from, target, _STATUS_DURATION)
	await _status_tween.finished
