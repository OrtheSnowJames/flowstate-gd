## Menu screen state machine -- root (Play/Settings) -> Play (Solo Play/
## Connect to Localhost/Back) -> Settings (four rows). Every screen is just a
## call to $UI/MenuScreen.show_buttons() (see menu/menu_screen.gd) with a
## different list; nothing here hand-places a button.
##
## Solo Play and Connect to Localhost are both one-line fire-and-forgets into
## Net (Net.start_solo_play()/start_connect_localhost()) rather than awaited
## here -- see the comment on those in net.gd. Both cross a
## change_scene_to_file() call, which frees THIS node partway through; an
## `await` here that spanned that boundary would be resuming a coroutine on
## a node that no longer exists.
extends Node3D

@onready var _menu_screen: Control = $UI/MenuScreen


func _ready() -> void:
	_show_root()


# ---------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------
func _show_root() -> void:
	_menu_screen.show_buttons([
		{"label": "Play", "on_press": _show_play},
		{"label": "Settings", "on_press": _show_settings},
	])


func _show_play() -> void:
	_menu_screen.show_buttons([
		{"label": "Solo Play", "on_press": _on_solo_play},
		{"label": "Connect to Localhost", "on_press": _on_connect_localhost},
		{"label": "Back", "on_press": _show_root},
	])


func _show_settings() -> void:
	_menu_screen.show_buttons([
		{"type": "stepper", "label": "Camera Height", "value": "%.1fm" % Settings.camera_hover_height,
			"on_left": _dec_camera_height, "on_right": _inc_camera_height},
		{"type": "stepper", "label": "Angle", "value": "%d°" % int(Settings.camera_pitch_deg),
			"on_left": _dec_camera_angle, "on_right": _inc_camera_angle},
		{"type": "stepper", "label": "A/D Sensitivity", "value": "%.1f" % Settings.turn_speed,
			"on_left": _dec_turn_speed, "on_right": _inc_turn_speed},
		{"label": "Exponential Sensitivity: %s" % (
			"On" if Settings.exponential_turn_sensitivity else "Off"),
			"on_press": _toggle_exponential_sensitivity},
		{"label": "Back", "on_press": _show_root},
	])


# ---------------------------------------------------------------------------
# Settings rows -- the three numeric ones are the_stepper.tscn rows (left
# arrow "-", right arrow "+", explicit direction instead of a single button
# cycling and wrapping around). Each arrow press clamps its value, saves,
# and returns the new amount text; menu_screen.gd sets that directly on the
# row's own amount_text, so only that one row's label changes -- no
# show_buttons() rebuild/transition of the whole screen on every click.
# ---------------------------------------------------------------------------
const _CAMERA_HEIGHT_MIN := 1.0
const _CAMERA_HEIGHT_MAX := 6.0
const _CAMERA_HEIGHT_STEP := 0.5

const _CAMERA_ANGLE_MIN := -70.0
const _CAMERA_ANGLE_MAX := -10.0
const _CAMERA_ANGLE_STEP := 5.0

const _TURN_SPEED_MIN := 0.5
const _TURN_SPEED_MAX := 6.0
const _TURN_SPEED_STEP := 0.5


func _dec_camera_height() -> String:
	Settings.camera_hover_height = _step_clamped(
		Settings.camera_hover_height, -_CAMERA_HEIGHT_STEP, _CAMERA_HEIGHT_MIN, _CAMERA_HEIGHT_MAX)
	Settings.save_settings()
	return "%.1fm" % Settings.camera_hover_height


func _inc_camera_height() -> String:
	Settings.camera_hover_height = _step_clamped(
		Settings.camera_hover_height, _CAMERA_HEIGHT_STEP, _CAMERA_HEIGHT_MIN, _CAMERA_HEIGHT_MAX)
	Settings.save_settings()
	return "%.1fm" % Settings.camera_hover_height


func _dec_camera_angle() -> String:
	Settings.camera_pitch_deg = _step_clamped(
		Settings.camera_pitch_deg, -_CAMERA_ANGLE_STEP, _CAMERA_ANGLE_MIN, _CAMERA_ANGLE_MAX)
	Settings.save_settings()
	return "%d°" % int(Settings.camera_pitch_deg)


func _inc_camera_angle() -> String:
	Settings.camera_pitch_deg = _step_clamped(
		Settings.camera_pitch_deg, _CAMERA_ANGLE_STEP, _CAMERA_ANGLE_MIN, _CAMERA_ANGLE_MAX)
	Settings.save_settings()
	return "%d°" % int(Settings.camera_pitch_deg)


func _dec_turn_speed() -> String:
	Settings.turn_speed = _step_clamped(
		Settings.turn_speed, -_TURN_SPEED_STEP, _TURN_SPEED_MIN, _TURN_SPEED_MAX)
	Settings.save_settings()
	return "%.1f" % Settings.turn_speed


func _inc_turn_speed() -> String:
	Settings.turn_speed = _step_clamped(
		Settings.turn_speed, _TURN_SPEED_STEP, _TURN_SPEED_MIN, _TURN_SPEED_MAX)
	Settings.save_settings()
	return "%.1f" % Settings.turn_speed


func _toggle_exponential_sensitivity() -> void:
	Settings.exponential_turn_sensitivity = not Settings.exponential_turn_sensitivity
	Settings.save_settings()
	_show_settings()


## Steps `value` by `step` (positive for the right/"+" arrow, negative for
## the left/"-" arrow) and clamps to [lo, hi] -- arrows have an explicit
## direction, so unlike the old single-button cycle, running off either end
## just stops there instead of wrapping around.
func _step_clamped(value: float, step: float, lo: float, hi: float) -> float:
	return clampf(value + step, lo, hi)


# ---------------------------------------------------------------------------
# Play
# ---------------------------------------------------------------------------
func _on_solo_play() -> void:
	Net.start_solo_play()


func _on_connect_localhost() -> void:
	Net.start_connect_localhost()
