# the waiting room everyone who connects sits here with no body in the pool
extends Node3D

const PLAYER_LIST := preload("res://menu/player_list.tscn")

@onready var _menu_screen: Control = $UI/MenuScreen
@onready var _count: Label = $UI/Count


func _ready() -> void:
	Net.lobby_changed.connect(_refresh)
	CouchParty.changed.connect(_refresh)
	# the host pressing start doesnt change the roster so it wouldnt reach _refresh through
	Net.round_loading.connect(_on_round_loading)
	_refresh()

	VoiceChat.prompt_setup($UI)


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
	_count.text = "%s\n%d / %d players  -  Red %d / Blue %d" % [Net.game_mode_name(), count, Net.MAX_PLAYERS, red, blue]
	$UI/RoomCode.text = "Room Code: " + Net.room_code if not Net.room_code.is_empty() else ""

	var choices: Array = []
	if multiplayer.is_server() or not Net.is_online():
		choices.append({"label": "Waiting for party..." if CouchParty.leader() and not CouchParty.ready_for_match() else "Start", "on_press": _on_start})
	else:
		choices.append({"label": "Waiting for host", "on_press": _noop})
	choices.append({"label": "View Players", "on_press": _on_view_players})
	if CouchParty.active():
		choices.append({"label": "Rooms", "on_press": CouchParty.open_panel})
	choices.append({"label": "Leave", "on_press": _on_leave})
	_menu_screen.show_buttons(choices)


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
	Transition.add_child(list)
	tree_exiting.connect(list.queue_free)
	list.open()


func _noop() -> void:
	pass


func _on_copy_code() -> void:
	if not Net.room_code.is_empty():
		DisplayServer.clipboard_set(Net.room_code)
