# host based multiplayer a listen server whoever hosts runs the world and plays in
extends Node

const PORT := 7654
const MAX_PLAYERS := 8
const PLAYER_SCENE := preload("res://water/player.tscn")
# the scenes script preloaded purely to reach its team enum by name below rather
const PLAYER_SCRIPT := preload("res://water/player.gd")
# the 3 2 1 go label instantiated into the arenas hud at round start
const COUNTDOWN_TEXT := preload("res://menu/appear_disappear_text.tscn")
# where connecting lands you a path rather than a preload menu lobby tscn instances
const LOBBY_SCENE := "res://menu/lobby.tscn"

# where join_game connects when called with no argument point this at a real address
var join_ip := "127.0.0.1"

# off by default on purpose pressing test_lifeguard_key see project godots input map l as
@export var enable_lifeguard_test_key: bool = true

# spawn point of the player that used to be baked into ocean1 tscn players
const _SPAWN_ORIGIN := Vector3(0.0, 15.134187, 0.0)
const _SPAWN_SPREAD := 2.5

# how far off the pools centre line each team starts in metres along z
const _TEAM_SPAWN_Z := 11.0
# gap between teammates along x the deep shallow axis
const _TEAM_SPAWN_SPACING := 3.0

func _ready() -> void:
	# connected once here rather than inside host_game hosting twice would otherwise stack duplicate connections
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# deferred because the scene tree isnt built yet during an autoload _ready
	call_deferred("_spawn_for_direct_scene_launch")
	# runs after the above so hosting sees any already spawned body and no ops
	call_deferred("_apply_command_line")


# opening water ocean1 tscn directly in the editor pressing play on the arena itself
func _spawn_for_direct_scene_launch() -> void:
	if _players_root() == null:
		return
	round_state = RoundState.PLAYING
	_assign_team(multiplayer.get_unique_id())
	net_report_name(Settings.player_name)
	_reset_round_scoreboard()
	_add_player(multiplayer.get_unique_id())


# lets two instances be launched straight into a session from a terminal godot host
func _apply_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			start_host_lobby()
		elif arg == "--join":
			start_connect(join_ip)
		elif arg.begins_with("--join="):
			start_connect(arg.trim_prefix("--join="))


# true once were hosting or connected guards the debug keys against re hosting on
func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null \
			and not (peer is OfflineMultiplayerPeer) \
			and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func host_game() -> Error:
	if is_online():
		push_warning("net: already online, ignoring host_game()")
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("net: couldn't host on port %d (error %d)" % [PORT, err])
		return err
	multiplayer.multiplayer_peer = peer
	# the host plays too so it takes a lobby slot and a side right
	round_state = RoundState.LOBBY
	_assign_team(multiplayer.get_unique_id())
	# direct call not update_my_name we only just became the host inside this very function
	net_report_name(Settings.player_name)
	lobby_changed.emit()
	print("net: hosting on port %d as peer %d" % [PORT, multiplayer.get_unique_id()])
	return OK


func join_game(ip := "") -> Error:
	if is_online():
		push_warning("net: already online, ignoring join_game()")
		return ERR_ALREADY_IN_USE
	var address := ip if ip != "" else join_ip
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("net: couldn't reach %s:%d (error %d)" % [address, PORT, err])
		return err
	# drop the solo body _ready spawned as a client our peer id wont be
	_clear_players()
	multiplayer.multiplayer_peer = peer
	print("net: connecting to %s:%d ..." % [address, PORT])
	return OK


func leave_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_clear_players()
	print("net: left the game")


# player bodies spawns a body for whichever peer this is right now in whatever
func spawn_local_player() -> void:
	_add_player(multiplayer.get_unique_id())


# where spawned players live the multiplayerspawner in ocean1 tscn watches this node so the
func _players_root() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Players") if scene else null


# removes every player body used when switching what session were in joining someone elses
func _clear_players() -> void:
	var players := _players_root()
	if players == null:
		return
	for child in players.get_children():
		players.remove_child(child)
		child.queue_free()


func _add_player(id: int) -> void:
	var players := _players_root()
	if players == null:
		# a warning not an error this fires on every scene load that doesnt want
		push_warning("net: no Players node in the current scene -- can't spawn peer %d" % id)
		return
	if players.has_node(str(id)):
		return
	var player := PLAYER_SCENE.instantiate()
	# the name is the peer id it replicates with the node and player gd
	player.name = str(id)
	# sides are settled back in the lobby well before anyone gets a body see
	if multiplayer.is_server() or not is_online():
		_assign_team(id)
	player.team = _teams.get(id, PLAYER_SCRIPT.Team.RED)
	# one per side rolled at round start see _pick_lifeguards set before add_child so the
	player.is_lifeguard = is_lifeguard_peer(id)
	player.position = spawn_position(id)
	player.rotation.y = spawn_rotation_y(id)
	# held still until the countdown finishes see _run_countdown set before add_child so a body
	player.movement_locked = round_state != RoundState.PLAYING
	players.add_child(player, true)
	# after add_child not before broadcasting the table is what actually gets the assignment to
	_broadcast_roster()
	print("net: spawned player for peer %d" % id)


# lobby and round lifecycle peers connect into a lobby and sit there with no
enum RoundState {
	LOBBY, # connected waiting for the host to start
	LOADING, # everyones switching to the arena host is waiting on them
	PLAYING, # bodies spawned countdown done or running
}
var round_state: RoundState = RoundState.LOBBY

# the lobby roster changed someone joined left or the team table arrived the lobby
signal lobby_changed
# the host has started everyone is loading the arena lets the lobby screen stop
signal round_loading

# host only which peers have told us theyve finished loading the arena see net_arena_ready
var _arena_ready: Dictionary = {}


# open a lobby and wait in it the hosts half of start_connect_localhost reached directly
func start_host_lobby() -> void:
	if is_online():
		push_warning("net: already online, ignoring start_host_lobby()")
		return
	host_game()
	await Transition.fade_to_black()
	get_tree().change_scene_to_file(LOBBY_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame
	await Transition.fade_from_black()


# drop out of the session and go back to the main menu separate from
func leave_lobby() -> void:
	leave_game()
	_teams.clear()
	_lifeguards.clear()
	_arena_ready.clear()
	round_state = RoundState.LOBBY
	await Transition.fade_to_black()
	get_tree().change_scene_to_file("res://menu/menu.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	await Transition.fade_from_black()


# how many peers are in the session host included the team table doubles as
func lobby_count() -> int:
	return _teams.size()


# host only put everyone in the pool safe to call twice the state check
func start_round() -> void:
	if not multiplayer.is_server() and is_online():
		push_warning("net: only the host can start the round")
		return
	if round_state != RoundState.LOBBY:
		return
	if is_online():
		rpc("net_load_arena")
	else:
		net_load_arena()


# everyone switch to the arena then report back the host doesnt spawn anybody until
@rpc("authority", "call_local", "reliable")
func net_load_arena() -> void:
	round_state = RoundState.LOADING
	round_loading.emit()
	_load_arena()


# deliberately leaves the screen black at the end rather than fading back in here
func _load_arena() -> void:
	await Transition.fade_to_black()
	get_tree().change_scene_to_file("res://water/ocean1.tscn")
	# wait for the players node to genuinely exist rather than counting frames and hoping
	var waited := 0.0
	while _players_root() == null and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if _players_root() == null:
		push_error("net: arena never came up -- can't join the round")
		return
	_apply_round_scoreboard_to_scene()
	# the arena and with it players multiplayerspawner exists now so its safe for the
	if is_online():
		rpc_id(1, "net_arena_ready")
	else:
		net_arena_ready()


# host only in practice a peer reporting its arena is up once everyone has
@rpc("any_peer", "call_local", "reliable")
func net_arena_ready() -> void:
	if is_online() and not multiplayer.is_server():
		return
	var who := multiplayer.get_remote_sender_id() if is_online() else 1
	if who == 0:
		who = multiplayer.get_unique_id() if is_online() else 1
	_arena_ready[who] = true
	if _everyone_ready():
		_begin_round()


func _everyone_ready() -> bool:
	if not is_online():
		return _arena_ready.has(1)
	if not _arena_ready.has(multiplayer.get_unique_id()):
		return false
	for id in multiplayer.get_peers():
		if not _arena_ready.has(id):
			return false
	return true


# host only spawn the whole roster then set everyone counting down
func _begin_round() -> void:
	round_state = RoundState.PLAYING
	_arena_ready.clear()
	_reset_round_scoreboard()
	# before any body is built so _add_player can set is_lifeguard from the roster as
	_pick_lifeguards()
	for id in _teams.keys():
		_add_player(id)
	if is_online():
		rpc("net_countdown")
	else:
		net_countdown()


# everyone hold the bodies still count in then hand control over driven by one
@rpc("authority", "call_local", "reliable")
func net_countdown() -> void:
	round_state = RoundState.PLAYING
	_run_countdown()


# the 3 2 1 go itself each number is one full play of menu
func _run_countdown() -> void:
	# lock first fade second the bodies exist by now and this is the last
	_set_movement_locked(true)
	await Transition.fade_from_black()
	var prompt := _ensure_message_text()
	for word in ["3", "2", "1", "GO!"]:
		if prompt and is_instance_valid(prompt):
			await prompt.play(word)
		else:
			await get_tree().create_timer(1.0).timeout
	_set_movement_locked(false)


# winning and losing set the moment a round is decided cleared once everyone is
var _round_over := false


# called from player gds net_death every time anybody goes under decides whether that finished
func on_player_down() -> void:
	if is_online() and not multiplayer.is_server():
		return
	if round_state != RoundState.PLAYING or _round_over:
		return
	var players := _players_root()
	if players == null:
		return

	# tally per side counting only sides somebody is actually playing an empty team must
	var total := {}
	var downed := {}
	for p in players.get_children():
		if not ("team" in p and "_unconscious" in p):
			continue
		total[p.team] = total.get(p.team, 0) + 1
		if p._unconscious:
			downed[p.team] = downed.get(p.team, 0) + 1
	if total.is_empty():
		return

	_remember_fainted_players(players)
	_sync_round_scoreboard()

	var any_wiped := false
	var winners := []
	for team in total:
		if downed.get(team, 0) >= total[team]:
			any_wiped = true
		else:
			winners.append(team)
	if not any_wiped:
		return

	# winners can legitimately come back empty both sides going under together or solo play
	_round_over = true
	if is_online():
		rpc("net_round_over", winners)
	else:
		net_round_over(winners)


# everyone freeze the pool open everyones eyes show this windows own verdict then head
@rpc("authority", "call_local", "reliable")
func net_round_over(winners: Array) -> void:
	_round_over = true
	# down tools immediately before anything else the round is decided the moment the last
	_set_movement_locked(true)
	# stop replicating here rather than just before the scene change nothing moves from this
	_silence_synchronizers()

	# revive before the banner not after the whole point of it is that the
	if not is_online() or multiplayer.is_server():
		_revive_everyone()

	var won := winners.has(team_of(multiplayer.get_unique_id()))
	var prompt := _ensure_message_text()
	if prompt and is_instance_valid(prompt):
		await prompt.play("YOU WIN" if won else "GET BETTER")
	else:
		await get_tree().create_timer(1.0).timeout

	# everyone not just the host each peer walks itself back out
	await _return_to_lobby()


# back to the waiting room after a round with the roster intact so the
func _return_to_lobby() -> void:
	round_state = RoundState.LOBBY
	_round_over = false
	_arena_ready.clear()
	_lifeguards.clear()
	await Transition.fade_to_black()
	get_tree().change_scene_to_file(LOBBY_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame
	await Transition.fade_from_black()


# stops the player bodies broadcasting as soon as the round is decided everyone is
func _silence_synchronizers() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	# the whole scene not just the player bodies the players were the obvious suspects
	for sync in _synchronizers_in(scene):
		sync.public_visibility = false


func _synchronizers_in(node: Node) -> Array[MultiplayerSynchronizer]:
	var found: Array[MultiplayerSynchronizer] = []
	if node is MultiplayerSynchronizer:
		found.append(node)
	for child in node.get_children():
		found.append_array(_synchronizers_in(child))
	return found


# opens everyones eyes again this is cosmetic not a second chance being knocked out
func _revive_everyone() -> void:
	var players := _players_root()
	if players == null:
		return
	for p in players.get_children():
		if p.has_method("revive"):
			p.revive()


# locks or releases every body in the arena applied to all of them not
func _set_movement_locked(locked: bool) -> void:
	var players := _players_root()
	if players == null:
		return
	for p in players.get_children():
		if "movement_locked" in p:
			p.movement_locked = locked


# round scoreboard
var _round_faints: Dictionary = {
	PLAYER_SCRIPT.Team.RED: {},
	PLAYER_SCRIPT.Team.BLUE: {},
}
var _round_red_score := 0
var _round_blue_score := 0
var _round_red_goal := 0
var _round_blue_goal := 0


func _reset_round_scoreboard() -> void:
	_round_faints[PLAYER_SCRIPT.Team.RED] = {}
	_round_faints[PLAYER_SCRIPT.Team.BLUE] = {}
	_sync_round_scoreboard()


func _remember_fainted_players(players: Node) -> void:
	for p in players.get_children():
		if not ("team" in p and "_unconscious" in p):
			continue
		if not p._unconscious:
			continue
		var scoring_team := _opponent_team(p.team)
		if scoring_team < 0:
			continue
		var id := String(p.name).to_int()
		if id <= 0:
			id = p.get_instance_id()
		_round_faints[scoring_team][id] = true


func _forget_round_faint(id: int) -> void:
	for team in _round_faints.keys():
		_round_faints[team].erase(id)


func _opponent_team(team: int) -> int:
	if team == PLAYER_SCRIPT.Team.RED:
		return PLAYER_SCRIPT.Team.BLUE
	if team == PLAYER_SCRIPT.Team.BLUE:
		return PLAYER_SCRIPT.Team.RED
	return -1


func _round_score_for(team: int) -> int:
	return int(_round_faints.get(team, {}).size())


func _round_goal_for(team: int) -> int:
	var opponent := _opponent_team(team)
	return _peers_on_team(opponent).size() if opponent >= 0 else 0


@rpc("authority", "call_local", "reliable")
func net_sync_round_scoreboard(red_score: int, blue_score: int, red_goal: int, blue_goal: int) -> void:
	_round_red_score = red_score
	_round_blue_score = blue_score
	_round_red_goal = red_goal
	_round_blue_goal = blue_goal
	_apply_round_scoreboard_to_scene()


func _sync_round_scoreboard() -> void:
	var red := _round_score_for(PLAYER_SCRIPT.Team.RED)
	var blue := _round_score_for(PLAYER_SCRIPT.Team.BLUE)
	var red_goal := _round_goal_for(PLAYER_SCRIPT.Team.RED)
	var blue_goal := _round_goal_for(PLAYER_SCRIPT.Team.BLUE)
	if is_online() and multiplayer.is_server():
		rpc("net_sync_round_scoreboard", red, blue, red_goal, blue_goal)
	else:
		net_sync_round_scoreboard(red, blue, red_goal, blue_goal)


func _apply_round_scoreboard_to_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var scoreboard := scene.get_node_or_null("Scoreboard")
	if scoreboard and scoreboard.has_method("set_round_progress"):
		scoreboard.set_round_progress(
			_round_red_score,
			_round_blue_score,
			_round_red_goal,
			_round_blue_goal)


# the big centred message label built on demand into the arenas hud layer shared
func _ensure_message_text() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var gui := scene.get_node_or_null("gui")
	if gui == null:
		return null
	var existing := gui.get_node_or_null("Message")
	if existing:
		return existing
	var prompt := COUNTDOWN_TEXT.instantiate()
	prompt.name = "Message"
	# no layout fixup needed here appear_disappear_text tscn anchors itself full rect root and its
	gui.add_child(prompt)
	return prompt


# teams whos on which side peer id player team the host owns this outright
var _teams: Dictionary = {}


# this peers idea of what side id is on or 1 if it hasnt
func team_of(id: int) -> int:
	return _teams.get(id, -1)


# assigns once and returns the side a peer plays for host only reached only
func _assign_team(id: int) -> int:
	if _teams.has(id):
		return _teams[id]
	var red := 0
	var blue := 0
	for t in _teams.values():
		if t == PLAYER_SCRIPT.Team.BLUE:
			blue += 1
		else:
			red += 1
	_teams[id] = PLAYER_SCRIPT.Team.BLUE if blue < red else PLAYER_SCRIPT.Team.RED
	return _teams[id]


# peer display name same host owned broadcast pattern as _teams and _lifeguards but the
var _names: Dictionary = {}

const _DEFAULT_NAME := "Player"
# keeps lobby rows and nameplates a sane width regardless of what got typed
const _MAX_NAME_LEN := 20


# ids chosen display name or a generic fallback if it hasnt reported one yet
func name_of(id: int) -> String:
	return _names.get(id, _DEFAULT_NAME)


# trims length caps and falls back to _default_name for anything thats blank after trimming
func _sanitize_name(raw: String) -> String:
	var trimmed := raw.strip_edges()
	if trimmed.is_empty():
		return _DEFAULT_NAME
	return trimmed.substr(0, _MAX_NAME_LEN)


# every peer calls this once its actually connected see _on_connected_to_server host_game _spawn_for_direct_scene_launch and again
@rpc("any_peer", "reliable")
func net_report_name(display_name: String) -> void:
	if is_online() and not multiplayer.is_server():
		return
	# get_remote_sender_id is 0 when this wasnt reached via an actual incoming rpc i e
	var sender := multiplayer.get_remote_sender_id()
	var id := sender if sender != 0 else multiplayer.get_unique_id()
	_names[id] = _sanitize_name(display_name)
	_broadcast_roster()
	lobby_changed.emit()


# sends this peers current settings player_name to whoever owns the roster the host itself
func update_my_name() -> void:
	if is_online() and not multiplayer.is_server():
		rpc_id(1, "net_report_name", Settings.player_name)
	else:
		net_report_name(Settings.player_name)


# each sides lifeguard player team peer id exactly one per team drawn at random
var _lifeguards: Dictionary = {}


# whether id is their teams lifeguard the only player who can revive see player
func is_lifeguard_peer(id: int) -> bool:
	var team := team_of(id)
	return team >= 0 and _lifeguards.get(team, 0) == id


# host only roll one lifeguard per team out of that teams current roster called
func _pick_lifeguards() -> void:
	_lifeguards.clear()
	for team in [PLAYER_SCRIPT.Team.RED, PLAYER_SCRIPT.Team.BLUE]:
		var roster := _peers_on_team(team)
		if roster.is_empty():
			continue
		_lifeguards[team] = roster[randi() % roster.size()]
	print("net: lifeguards %s" % _lifeguards)


# host everyone the whole roster whos on which side who each sides lifeguard is
@rpc("authority", "call_local", "reliable")
func net_sync_roster(teams: Dictionary, lifeguards: Dictionary, names: Dictionary) -> void:
	_teams = teams.duplicate()
	_lifeguards = lifeguards.duplicate()
	_names = names.duplicate()
	_apply_teams_to_bodies()
	# this table is also the lobby roster see lobby_count receiving it is how a
	lobby_changed.emit()


# pushes the current roster onto whatever bodies exist right now called both when the
func _apply_teams_to_bodies() -> void:
	var players := _players_root()
	if players == null:
		return
	for p in players.get_children():
		var pid := String(p.name).to_int()
		if pid <= 0:
			continue
		if _teams.has(pid) and "team" in p:
			p.team = _teams[pid]
		# assigned from the roster not left to the scene default the whole point is
		if "is_lifeguard" in p:
			p.is_lifeguard = is_lifeguard_peer(pid)


# host only hand the current roster to everybody no op offline where theres nobody
func _broadcast_roster() -> void:
	if not is_online() or not multiplayer.is_server():
		return
	rpc("net_sync_roster", _teams, _lifeguards, _names)


# where the body belonging to id starts and which way it faces the pools
func spawn_position(id: int) -> Vector3:
	var team := team_of(id)
	if team < 0:
		# no team known solo play or a body spawned before the table arrived fall
		var slot := absi(id) % MAX_PLAYERS
		var angle := float(slot) * TAU / float(MAX_PLAYERS)
		return _SPAWN_ORIGIN + Vector3(cos(angle), 0.0, sin(angle)) * _SPAWN_SPREAD

	# spread teammates along x the deep shallow axis and centre the row on x
	var mates := _peers_on_team(team)
	var slot := maxi(mates.find(id), 0)
	var offset := (float(slot) - float(maxi(mates.size(), 1) - 1) * 0.5) * _TEAM_SPAWN_SPACING
	var z := -_TEAM_SPAWN_Z if team == PLAYER_SCRIPT.Team.RED else _TEAM_SPAWN_Z
	return Vector3(offset, _SPAWN_ORIGIN.y, z)


# which way the body belonging to id faces on spawn across the pool at
func spawn_rotation_y(id: int) -> float:
	var team := team_of(id)
	if team < 0:
		return 0.0
	# red is on z and needs to face z toward blue pi blue is
	return PI if team == PLAYER_SCRIPT.Team.RED else 0.0


# every peer on team sorted so which slot am i is the same answer
func _peers_on_team(team: int) -> Array:
	var out := []
	for id in _teams:
		if _teams[id] == team:
			out.append(id)
	out.sort()
	return out


func _on_peer_connected(id: int) -> void:
	print("net: peer %d connected" % id)
	# a client hears about the server connecting and nothing else enet is client server
	if not multiplayer.is_server():
		return
	# a lobby slot first and only then if theres already a round running a
	_assign_team(id)
	_broadcast_roster()
	if round_state == RoundState.PLAYING:
		# joining mid round straight into the pool rather than being stuck watching from a
		_add_player(id)
		_sync_round_scoreboard()
	lobby_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	print("net: peer %d disconnected" % id)
	if not multiplayer.is_server():
		return
	var players := _players_root()
	if players and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
	# drop them from the roster too or the lobby keeps counting someone who left
	var was_team := team_of(id)
	var was_lifeguard := is_lifeguard_peer(id)
	_teams.erase(id)
	_arena_ready.erase(id)
	_forget_round_faint(id)
	# a lifeguard who quits isnt the same as one whos been knocked out the
	if was_lifeguard:
		_lifeguards.erase(was_team)
		var remaining := _peers_on_team(was_team)
		if not remaining.is_empty():
			_lifeguards[was_team] = remaining[randi() % remaining.size()]
			print("net: lifeguard %d left, %d takes over for team %d" % [
				id, _lifeguards[was_team], was_team])
	_broadcast_roster()
	if round_state == RoundState.PLAYING:
		_sync_round_scoreboard()
	lobby_changed.emit()
	# they may have been the last peer the host was waiting on before it
	if round_state == RoundState.LOADING and _everyone_ready():
		_begin_round()


func _on_connected_to_server() -> void:
	print("net: connected as peer %d" % multiplayer.get_unique_id())
	# the host has no way to know our chosen name until we tell it
	update_my_name()


func _on_connection_failed() -> void:
	push_error("net: connection failed")
	multiplayer.multiplayer_peer = null


func _on_server_disconnected() -> void:
	push_warning("net: host closed the game")
	leave_game()


# menu flow orchestration these two exist here not in menu gd for a real

# solo play a one player round runs the exact same load everyone ready spawn
func start_solo_play() -> void:
	# a roster of exactly us cleared first so a previous sessions leftovers cant put
	_teams.clear()
	_lifeguards.clear()
	_arena_ready.clear()
	_assign_team(multiplayer.get_unique_id())
	net_report_name(Settings.player_name)
	round_state = RoundState.LOBBY
	start_round()


# connect to localhost lands in the lobby either way joining an existing one if
func start_connect_localhost() -> void:
	await Transition.blur_in()
	Transition.show_status("Connecting...")
	get_tree().change_scene_to_file(LOBBY_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame

	var err := join_game("127.0.0.1")
	var ok := false
	if err == OK:
		ok = await _await_connection_result()
	if ok:
		await Transition.hide_status()
		await Transition.blur_out()
		return

	# nobodys home undo whatever join_game left behind before hosting on a hard refusal _on_connection_failed
	if is_online():
		leave_game()
	Transition.show_status("Starting a lobby...")
	host_game()
	await get_tree().create_timer(0.3).timeout
	await Transition.hide_status()
	await Transition.blur_out()


# the whole join somebodys game flow address and all split out of start_connect_localhost so
func start_connect(ip: String) -> void:
	await Transition.blur_in()
	Transition.show_status("Connecting...")
	get_tree().change_scene_to_file(LOBBY_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame

	var err := join_game(ip)
	# not err ok and await an explicit if instead of leaning on ands short
	var ok := false
	if err == OK:
		ok = await _await_connection_result()
	if ok:
		await Transition.hide_status()
		await Transition.blur_out()
		return

	await Transition.show_status("Couldn't connect")
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://menu/menu.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	await Transition.hide_status()
	await Transition.blur_out()


# set while _await_connection_result is waiting see there
var _awaiting_connection := false
var _connection_succeeded := false

# races multiplayers own connected_to_server connection_failed signals join_game already wires the general purpose _on_connected_to_server _on_connection_failed
func _await_connection_result(timeout := 8.0) -> bool:
	_awaiting_connection = true
	_connection_succeeded = false
	multiplayer.connected_to_server.connect(_on_connect_attempt_ok, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connect_attempt_failed, CONNECT_ONE_SHOT)
	var elapsed := 0.0
	while _awaiting_connection and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if multiplayer.connected_to_server.is_connected(_on_connect_attempt_ok):
		multiplayer.connected_to_server.disconnect(_on_connect_attempt_ok)
	if multiplayer.connection_failed.is_connected(_on_connect_attempt_failed):
		multiplayer.connection_failed.disconnect(_on_connect_attempt_failed)
	return _connection_succeeded


func _on_connect_attempt_ok() -> void:
	_connection_succeeded = true
	_awaiting_connection = false


func _on_connect_attempt_failed() -> void:
	_connection_succeeded = false
	_awaiting_connection = false


# debug keys placeholder until the real menu ui exists raw keycodes rather than input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				# opens a lobby and waits in it same as host the old behaviour opening
				if not is_online():
					start_host_lobby()
			KEY_F2:
				# start_connect not the bare join_game opening the connection without also getting into the lobby
				if not is_online():
					start_connect(join_ip)
	if enable_lifeguard_test_key and event.is_action_pressed("test_lifeguard_key"):
		_toggle_local_lifeguard()


# flips is_lifeguard on whichever player body belongs to this peer for testing the buffs
func _toggle_local_lifeguard() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			p.is_lifeguard = not p.is_lifeguard
			print("net: test_lifeguard_key -> %s is_lifeguard=%s" % [p.name, p.is_lifeguard])
			return
