# menu screen state machine root play settings play solo play connect to localhost back
extends Node3D

const NAME_PROMPT := preload("res://menu/name_prompt.tscn")
const SERVER_PROMPT := preload("res://menu/server_prompt.tscn")

@onready var _menu_screen: Control = $UI/MenuScroll/MenuScreen


func _ready() -> void:
	_show_root()


# screens
func _show_root() -> void:
	_menu_screen.show_buttons([
		{"label": "Play", "on_press": _show_play},
		{"label": "Settings", "on_press": _show_settings},
	])


func _show_play() -> void:
	var connect_label := "Connect to Localhost"
	if Net.online_penalty_remaining() > 0:
		connect_label = "Online Penalty: %s" % Net.online_penalty_text()
	_menu_screen.show_buttons([
		{"label": "Quick Play", "on_press": Matchmaking.quick_play},
		{"label": "Join Code", "on_press": _open_code_prompt},
		{"label": "Solo Play", "on_press": _on_solo_play},
		{"label": connect_label, "on_press": _on_connect_localhost},
		{"label": "Custom Server", "on_press": _show_custom_server},
		{"label": "Back", "on_press": _show_root},
	])


func _show_custom_server() -> void:
	_menu_screen.show_buttons([
		{"label": "Join", "on_press": _open_server_prompt.bind(false)},
		{"label": "Host", "on_press": _open_server_prompt.bind(true)},
		{"label": "Back", "on_press": _show_play},
	])


func _open_server_prompt(hosting: bool) -> void:
	if $UI.has_node("ServerPrompt"):
		return
	var prompt := SERVER_PROMPT.instantiate()
	$UI.add_child(prompt)
	prompt.open(hosting)
	prompt.submitted.connect(func(ip: String, port: int) -> void:
		if hosting:
			if Matchmaking.configured():
				Matchmaking.host_match(port)
			else:
				Net.start_host_lobby(port)
		else:
			Net.start_connect(ip, port))


func _open_code_prompt() -> void:
	if $UI.has_node("ServerPrompt"):
		return
	var prompt := SERVER_PROMPT.instantiate()
	$UI.add_child(prompt)
	prompt.open_code()
	prompt.code_submitted.connect(Matchmaking.join_code)


func _show_settings() -> void:
	_menu_screen.show_buttons([
		{"label": "Name: %s" % Settings.player_name, "on_press": _on_edit_name},
		{"type": "stepper", "label": "Camera Height", "value": "%.1fm" % Settings.camera_hover_height,
			"on_left": _dec_camera_height, "on_right": _inc_camera_height},
		{"type": "stepper", "label": "Angle", "value": "%d°" % int(Settings.camera_pitch_deg),
			"on_left": _dec_camera_angle, "on_right": _inc_camera_angle},
		{"type": "stepper", "label": "A/D Sensitivity", "value": "%.1f" % Settings.turn_speed,
			"on_left": _dec_turn_speed, "on_right": _inc_turn_speed},
		{"label": "Exponential Sensitivity: %s" % (
			"On" if Settings.exponential_turn_sensitivity else "Off"),
			"on_press": _toggle_exponential_sensitivity},
		{"label": "Performance Mode: %s" % ("On" if Settings.performance_mode else "Off"),
			"on_press": _toggle_performance_mode},
		{"label": "Back", "on_press": _show_root},
	])


# opens the same modal the lobbys first join prompt uses pre filled with the
func _on_edit_name() -> void:
	var prompt := NAME_PROMPT.instantiate()
	$UI.add_child(prompt)
	prompt.open(Settings.player_name, "Enter your name", _on_name_confirmed, _on_name_canceled)


func _on_name_confirmed(new_name: String) -> void:
	Settings.player_name = new_name
	Settings.save_settings()
	Net.update_my_name()
	_show_settings()


func _on_name_canceled() -> void:
	# nothing to do the settings screen was never replaced while the prompt was open
	pass


# settings rows the three numeric ones are the_stepper tscn rows left arrow right arrow
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


func _toggle_performance_mode() -> void:
	Settings.performance_mode = not Settings.performance_mode
	Settings.save_settings()
	_show_settings()


# steps value by step positive for the right arrow negative for the left arrow
func _step_clamped(value: float, step: float, lo: float, hi: float) -> float:
	return clampf(value + step, lo, hi)


# play
func _on_solo_play() -> void:
	Net.start_solo_play()


func _on_connect_localhost() -> void:
	Net.start_connect_localhost()
