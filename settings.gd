## Persisted player-tunable settings -- camera height/angle and A/D turning
## feel. Applied to whichever player body is local (see apply_to(), called
## from water/player.gd's _ready()) and edited from menu.gd's Settings
## screen, which calls save_settings() after every change.
##
## Defaults match water/player.gd's own export defaults exactly, so a fresh
## install (no user://settings.cfg yet) behaves identically to a player who's
## never touched Settings at all.
extends Node

const _SAVE_PATH := "user://settings.cfg"
const _SECTION := "camera"

## CamPivot's height above the player -- "camera arc" in the Settings screen.
## See water/player.tscn's CamPivot and water/player.gd's camera_hover_height.
var camera_hover_height: float = 3.2
## Fixed look-down angle in degrees -- "angle". See water/player.gd's
## default_camera_pitch_deg.
var camera_pitch_deg: float = -36.0
## A/D turn rate in rad/s -- "A/D sensitivity". See water/player.gd's
## turn_speed.
var turn_speed: float = 2.5
## Whether A/D turning ramps up the longer the key is held (on) or applies
## the full turn_speed instantly (off, the default) -- "exponential
## sensitivity". See water/player.gd's exponential_turn_sensitivity.
var exponential_turn_sensitivity: bool = false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	# A missing/corrupt file just means "nothing saved yet" -- the defaults
	# above already match a fresh install, so there's nothing else to do.
	if cfg.load(_SAVE_PATH) != OK:
		return
	camera_hover_height = cfg.get_value(_SECTION, "camera_hover_height", camera_hover_height)
	camera_pitch_deg = cfg.get_value(_SECTION, "camera_pitch_deg", camera_pitch_deg)
	turn_speed = cfg.get_value(_SECTION, "turn_speed", turn_speed)
	exponential_turn_sensitivity = cfg.get_value(
		_SECTION, "exponential_turn_sensitivity", exponential_turn_sensitivity)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, "camera_hover_height", camera_hover_height)
	cfg.set_value(_SECTION, "camera_pitch_deg", camera_pitch_deg)
	cfg.set_value(_SECTION, "turn_speed", turn_speed)
	cfg.set_value(_SECTION, "exponential_turn_sensitivity", exponential_turn_sensitivity)
	var err := cfg.save(_SAVE_PATH)
	if err != OK:
		push_error("Settings: couldn't save %s (error %d)" % [_SAVE_PATH, err])


## Pushes these values onto a player body's matching exports. Only makes
## sense for the LOCAL player -- see water/player.gd's _ready(), which only
## calls this in the local-player branch. Duck-typed rather than statically
## typed as the Player script, so this file stays decoupled from
## water/player.gd's exact class.
func apply_to(player: Node) -> void:
	player.camera_hover_height = camera_hover_height
	player.default_camera_pitch_deg = camera_pitch_deg
	player.turn_speed = turn_speed
	player.exponential_turn_sensitivity = exponential_turn_sensitivity
