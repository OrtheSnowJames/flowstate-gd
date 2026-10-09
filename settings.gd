# persisted player tunable settings camera height angle and a d turning feel applied to
extends Node

const _SAVE_PATH := "user://settings.cfg"
const _SECTION := "camera"
const _PROFILE_SECTION := "profile"

# display name shown to other players the lobbys player list everyone and a floating
var player_name: String = ""

# campivots height above the player camera arc in the settings screen see water player
var camera_hover_height: float = 3.2
# fixed look down angle in degrees angle see water player gds default_camera_pitch_deg
var camera_pitch_deg: float = -36.0
# a d turn rate in rad s a d sensitivity see water player gds
var turn_speed: float = 2.5
# whether a d turning ramps up the longer the key is held on or
var exponential_turn_sensitivity: bool = false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	# a missing corrupt file just means nothing saved yet the defaults above already match
	if cfg.load(_SAVE_PATH) != OK:
		return
	camera_hover_height = cfg.get_value(_SECTION, "camera_hover_height", camera_hover_height)
	camera_pitch_deg = cfg.get_value(_SECTION, "camera_pitch_deg", camera_pitch_deg)
	turn_speed = cfg.get_value(_SECTION, "turn_speed", turn_speed)
	exponential_turn_sensitivity = cfg.get_value(
		_SECTION, "exponential_turn_sensitivity", exponential_turn_sensitivity)
	player_name = cfg.get_value(_PROFILE_SECTION, "player_name", player_name)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, "camera_hover_height", camera_hover_height)
	cfg.set_value(_SECTION, "camera_pitch_deg", camera_pitch_deg)
	cfg.set_value(_SECTION, "turn_speed", turn_speed)
	cfg.set_value(_SECTION, "exponential_turn_sensitivity", exponential_turn_sensitivity)
	cfg.set_value(_PROFILE_SECTION, "player_name", player_name)
	var err := cfg.save(_SAVE_PATH)
	if err != OK:
		push_error("Settings: couldn't save %s (error %d)" % [_SAVE_PATH, err])


# pushes these values onto a player bodys matching exports only makes sense for the
func apply_to(player: Node) -> void:
	player.camera_hover_height = camera_hover_height
	player.default_camera_pitch_deg = camera_pitch_deg
	player.turn_speed = turn_speed
	player.exponential_turn_sensitivity = exponential_turn_sensitivity
