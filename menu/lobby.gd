# the waiting room everyone who connects sits here with no body in the pool
extends Node3D

const NAME_PROMPT := preload("res://menu/name_prompt.tscn")
const PLAYER_LIST := preload("res://menu/player_list.tscn")

@onready var _menu_screen: Control = $UI/MenuScreen
@onready var _count: Label = $UI/Count


func _ready() -> void:
	Net.lobby_changed.connect(_refresh)
	# the host pressing start doesnt change the roster so it wouldnt reach _refresh through
	Net.round_loading.connect(_on_round_loading)
	_refresh()

	# first time anyones ever landed in a lobby on this install settings has no
	if Settings.player_name.is_empty():
		var prompt := NAME_PROMPT.instantiate()
		$UI.add_child(prompt)
		prompt.open("", "Enter your name", _on_name_chosen)


func _on_name_chosen(new_name: String) -> void:
	Settings.player_name = new_name
	Settings.save_settings()
	Net.update_my_name()


func _exit_tree() -> void:
	# the lobby dies on every scene change net doesnt leaving these connected would have
	if Net.lobby_changed.is_connected(_refresh):
		Net.lobby_changed.disconnect(_refresh)
	if Net.round_loading.is_connected(_on_round_loading):
		Net.round_loading.disconnect(_on_round_loading)


func _refresh() -> void:
	var count := Net.lobby_count()
	var red := 0
	var blue := 0
	for id in Net._teams:
		if Net._teams[id] == PLAYER_SCRIPT.Team.BLUE:
			blue += 1
		else:
			red += 1
	_count.text = "%d %s in the lobby\nRed %d  -  Blue %d" % [
		count, "player" if count == 1 else "players", red, blue]

	# only the host can start everyone else is told what theyre waiting for is_server
	if multiplayer.is_server() or not Net.is_online():
		_menu_screen.show_buttons([
			{"label": "Start", "on_press": _on_start},
			{"label": "View Players", "on_press": _on_view_players},
			{"label": "Leave", "on_press": _on_leave},
		])
	else:
		_menu_screen.show_buttons([
			{"label": "Waiting for host", "on_press": _noop},
			{"label": "View Players", "on_press": _on_view_players},
			{"label": "Leave", "on_press": _on_leave},
		])


const PLAYER_SCRIPT := preload("res://water/player.gd")


func _on_round_loading() -> void:
	_menu_screen.show_buttons([{"label": "Starting...", "on_press": _noop}])


func _on_start() -> void:
	# fire and forget into net exactly like menu gds solo play start_round leads to
	Net.start_round()


func _on_leave() -> void:
	Net.leave_lobby()


# fire and forget player_list gd owns its whole open blur close cycle and frees
func _on_view_players() -> void:
	var list := PLAYER_LIST.instantiate()
	$UI.add_child(list)
	list.open()


func _noop() -> void:
	pass
