## The waiting room. Everyone who connects sits here -- with no body in the
## pool yet -- until the host starts the round.
##
## Reads its roster straight off Net (lobby_count/team_of), redrawing whenever
## Net says it changed rather than polling, so a client that only ever hears
## about other players through the synced team table still shows an accurate
## count. See net.gd's lobby_count() for why that table is the roster.
extends Node3D

@onready var _menu_screen: Control = $UI/MenuScreen
@onready var _count: Label = $UI/Count


func _ready() -> void:
	Net.lobby_changed.connect(_refresh)
	# The host pressing Start doesn't change the roster, so it wouldn't reach
	# _refresh through lobby_changed -- but the button has to stop being
	# offered the moment it's pressed, or an impatient host gets two rounds
	# loading on top of each other.
	Net.round_loading.connect(_on_round_loading)
	_refresh()


func _exit_tree() -> void:
	# The lobby dies on every scene change; Net doesn't. Leaving these
	# connected would have Net calling into a freed node the next time anyone
	# joins or leaves.
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

	# Only the host can start; everyone else is told what they're waiting for.
	# is_server() is false offline, so the `or not Net.is_online()` keeps a
	# not-yet-hosting local session (which is its own host by definition) able
	# to start rather than waiting forever on nobody.
	if multiplayer.is_server() or not Net.is_online():
		_menu_screen.show_buttons([
			{"label": "Start", "on_press": _on_start},
			{"label": "Leave", "on_press": _on_leave},
		])
	else:
		_menu_screen.show_buttons([
			{"label": "Waiting for host", "on_press": _noop},
			{"label": "Leave", "on_press": _on_leave},
		])


const PLAYER_SCRIPT := preload("res://water/player.gd")


func _on_round_loading() -> void:
	_menu_screen.show_buttons([{"label": "Starting...", "on_press": _noop}])


func _on_start() -> void:
	# Fire-and-forget into Net, exactly like menu.gd's Solo Play: start_round()
	# leads to a change_scene_to_file() that frees THIS node partway through,
	# so an await here would resume a coroutine on a node that no longer
	# exists. Net is an autoload and survives the switch.
	Net.start_round()


func _on_leave() -> void:
	Net.leave_lobby()


func _noop() -> void:
	pass
