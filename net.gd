## Host-based multiplayer (a listen server): whoever hosts runs the world AND
## plays in it. There's no dedicated-server build and nothing here assumes one.
##
## Connecting is hardcoded for now -- see join_ip and the F1/F2 debug keys at
## the bottom. host_game()/join_game() are the entire public API, so a menu UI
## can drive this later by calling them and deleting _unhandled_input.
##
## Who owns what:
##  - Each player body is owned by the peer it belongs to (see player.gd's
##    _enter_tree), which broadcasts its own position/animation and decides its
##    own stamina and death.
##  - The host owns the world: PushCube's physics, and spawning/despawning the
##    player bodies themselves.
extends Node

const PORT := 7654
const MAX_PLAYERS := 8
const PLAYER_SCENE := preload("res://water/player.tscn")
## The scene's script, preloaded purely to reach its Team enum by name below
## rather than writing bare 0/1 here. player.gd has no class_name (nothing in
## this project does -- it's duck-typed throughout), so this is how the enum
## gets a qualified name on this side.
const PLAYER_SCRIPT := preload("res://water/player.gd")
## The 3-2-1-GO! label. Instantiated into the arena's HUD at round start --
## see _ensure_countdown_text().
const COUNTDOWN_TEXT := preload("res://menu/appear_disappear_text.tscn")
## Where connecting lands you. A path rather than a preload: menu/lobby.tscn
## instances ocean1.tscn for its background, and preloading it here (from an
## autoload, which resolves before the scene tree exists) would drag that whole
## arena in at boot.
const LOBBY_SCENE := "res://menu/lobby.tscn"

## Where join_game() connects when called with no argument. Point this at a
## real address (or read it off a UI field) to play over a network.
var join_ip := "127.0.0.1"

## Off by default, on purpose: pressing test_lifeguard_key (see project.godot's
## input map -- "L" as of writing) with this off does nothing at all. Unlike
## the F1/F2 host/join keys (harmless if someone leaves them in and presses
## one by accident), a live lifeguard toggle is a permanent gameplay-changing
## buff -- a stray keypress handing that out for real is worth its own
## explicit switch, not just "delete before shipping" discipline. Flip this
## on in the Inspector only while actually testing is_lifeguard.
@export var enable_lifeguard_test_key: bool = true

## Spawn point of the player that used to be baked into ocean1.tscn. Players
## are fanned out around it so two peers don't spawn inside each other.
const _SPAWN_ORIGIN := Vector3(0.0, 15.134187, 0.0)
const _SPAWN_SPREAD := 2.5

## How far off the pool's centre line each team starts, in metres along Z --
## the axis the teams are split on (see spawn_position). The water box is 46
## deep (ocean1.tscn's "water base" size), so ±11 puts each team in the middle
## of its own half rather than pinned against the back wall.
const _TEAM_SPAWN_Z := 11.0
## Gap between teammates along X, the deep/shallow axis.
const _TEAM_SPAWN_SPACING := 3.0

func _ready() -> void:
	# Connected once here rather than inside host_game(): hosting twice would
	# otherwise stack duplicate connections and spawn two bodies per peer.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Deferred because the scene tree isn't built yet during an autoload _ready.
	call_deferred("_spawn_for_direct_scene_launch")
	# Runs after the above, so hosting sees any already-spawned body and
	# no-ops on it, and joining clears it.
	call_deferred("_apply_command_line")


## Opening water/ocean1.tscn directly -- in the editor, pressing play on the
## arena itself rather than coming through the menu -- still has to put a
## usable body in the pool. The player used to be baked into that scene, and
## taking it out to spawn per-peer would otherwise leave that workflow with
## nothing to control.
##
## Marking the round live before spawning is the load-bearing part, not
## incidental: bodies now spawn movement_locked and are released by the
## countdown (see _add_player/_run_countdown), and there's no lobby, no host
## and no countdown anywhere in this path -- so without this the body would
## come up frozen with nothing left to ever unlock it.
##
## Boots that DO come through the menu land here first with no Players node at
## all (menu.tscn and lobby.tscn both set delete_players), and just return.
func _spawn_for_direct_scene_launch() -> void:
	if _players_root() == null:
		return
	round_state = RoundState.PLAYING
	_assign_team(multiplayer.get_unique_id())
	_add_player(multiplayer.get_unique_id())


## Lets two instances be launched straight into a session from a terminal:
##   godot -- --host
##   godot -- --join=192.168.1.42
## purely so multiplayer can be tested without alt-tabbing to press F1/F2.
## The debug keys and join_ip still work exactly the same; delete this along
## with _unhandled_input when the menu UI lands.
##
## --host opens a lobby and waits in it, rather than dropping straight into
## the pool: that's what hosting means now (see start_round). The round begins
## when someone presses Start, so a peer connecting with --join lands in the
## same lobby and both go in together.
func _apply_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			start_host_lobby()
		elif arg == "--join":
			start_connect(join_ip)
		elif arg.begins_with("--join="):
			start_connect(arg.trim_prefix("--join="))


## True once we're hosting or connected -- guards the debug keys against
## re-hosting on top of a live session.
##
## The OfflineMultiplayerPeer check is load-bearing, not defensive: Godot always
## has a multiplayer_peer set, defaulting to an OfflineMultiplayerPeer that
## reports itself CONNECTION_CONNECTED. A plain null/status check is therefore
## true even when nothing is networked, which made this return true before the
## first connection and silently refuse every host_game()/join_game() call.
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
	# The host plays too, so it takes a lobby slot (and a side) right away --
	# but NOT a body. Bodies are spawned by a round starting, not by connecting
	# (see start_round); handing the host one here would leave it swimming
	# around on its own while everyone else is still sitting in the lobby.
	# Callers that want to go straight into the pool without a lobby say so
	# explicitly -- see start_solo_play() and the --host command line.
	round_state = RoundState.LOBBY
	_assign_team(multiplayer.get_unique_id())
	_broadcast_teams()
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
	# Drop the solo body _ready spawned. As a client our peer id won't be 1 any
	# more, so that body isn't ours -- and the host's MultiplayerSpawner is
	# about to send us the real roster, this one included, which would collide
	# with it by name.
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


# ---------------------------------------------------------------------------
# Player bodies
# ---------------------------------------------------------------------------
## Spawns a body for whichever peer this is, right now, in whatever scene is
## currently active. _ready()'s own deferred spawn only ever fires once, at
## boot, against whichever scene happened to be current then -- with menu.tscn
## as run/main_scene that's the menu itself (no "Players" node, so it's a
## no-op there), so Solo Play needs its own explicit spawn once it's actually
## switched to a scene that has one. See menu.gd's Solo Play handler.
func spawn_local_player() -> void:
	_add_player(multiplayer.get_unique_id())


## Where spawned players live. The MultiplayerSpawner in ocean1.tscn watches
## this node, so the host adding a child here is what replicates it to every
## client -- clients never add players themselves.
func _players_root() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Players") if scene else null


## Removes every player body. Used when switching what session we're in --
## joining someone else's game, or leaving one -- so stale bodies from the
## previous state can't linger or collide by name with the incoming roster.
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
		# A warning, not an error: this fires on every scene load that doesn't
		# want the networked player roster at all -- the menu background (see
		# menu/menu.gd) drops its own standalone player.tscn instance directly
		# instead, deliberately outside this system. That's a legitimate scene,
		# not a bug, so this shouldn't read as one in the log.
		push_warning("net: no Players node in the current scene -- can't spawn peer %d" % id)
		return
	if players.has_node(str(id)):
		return
	var player := PLAYER_SCENE.instantiate()
	# The name IS the peer id: it replicates with the node, and player.gd reads
	# it back in _enter_tree to decide who controls this body. Set before
	# add_child so the name is already right when the node enters the tree.
	player.name = str(id)
	# Sides are settled back in the lobby, well before anyone gets a body (see
	# _assign_team, called from _on_peer_connected). By the time a round starts
	# the table has been synced to everyone, so both ends work out the same
	# spawn point for the same player without it having to be sent.
	if multiplayer.is_server() or not is_online():
		_assign_team(id)
	player.team = _teams.get(id, PLAYER_SCRIPT.Team.RED)
	player.position = spawn_position(id)
	player.rotation.y = spawn_rotation_y(id)
	# Held still until the countdown finishes -- see _run_countdown(). Set
	# before add_child so a body is locked from the very first frame it
	# exists, rather than getting one free frame of input.
	player.movement_locked = round_state != RoundState.PLAYING
	players.add_child(player, true)
	# After add_child, not before: broadcasting the table is what actually gets
	# the assignment to the clients, and it has to follow the spawn packet so
	# the body it refers to already exists on the other end.
	_broadcast_teams()
	print("net: spawned player for peer %d" % id)


# ---------------------------------------------------------------------------
# Lobby and round lifecycle
# ---------------------------------------------------------------------------
## Peers connect into a lobby and sit there with no bodies in the world at
## all; the host pressing Start is what puts everyone in the pool. That's the
## whole reason for this state: it tells _on_peer_connected whether a peer
## joining should get a body right now (mid-round) or just a lobby slot.
enum RoundState {
	LOBBY,    ## connected, waiting for the host to start
	LOADING,  ## everyone's switching to the arena; host is waiting on them
	PLAYING,  ## bodies spawned, countdown done or running
}
var round_state: RoundState = RoundState.LOBBY

## The lobby roster changed -- someone joined, left, or the team table
## arrived. The lobby UI redraws off this rather than polling.
signal lobby_changed
## The host has started; everyone is loading the arena. Lets the lobby screen
## stop offering a Start button the moment it's been pressed.
signal round_loading

## Host-only: which peers have told us they've finished loading the arena (see
## net_arena_ready). Spawning before a client's MultiplayerSpawner exists means
## the spawn packet lands with nowhere to route -- the same failure that shaped
## start_connect()'s scene-then-connect ordering -- so the host waits for this
## set to fill rather than guessing at a delay.
var _arena_ready: Dictionary = {}


## Open a lobby and wait in it. The host's half of start_connect_localhost(),
## reached directly by --host and F1 rather than by trying to connect to
## yourself first and failing.
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


## Drop out of the session and go back to the main menu. Separate from
## leave_game() (which only tears down the connection) because the lobby needs
## the scene change too, and that has to happen from an autoload -- it frees
## the lobby node partway through.
func leave_lobby() -> void:
	leave_game()
	_teams.clear()
	_arena_ready.clear()
	round_state = RoundState.LOBBY
	await Transition.fade_to_black()
	get_tree().change_scene_to_file("res://menu/menu.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	await Transition.fade_from_black()


## How many peers are in the session, host included. The team table doubles as
## the lobby roster: the host writes an entry the moment a peer connects and
## broadcasts the whole thing, so every peer already has the full list without
## needing a second roster message of its own. (ENet's client/server topology
## means clients never see each other's peer_connected -- they only ever hear
## about the server -- so this table is genuinely the only roster they get.)
func lobby_count() -> int:
	return _teams.size()


## Host-only: put everyone in the pool. Safe to call twice -- the state check
## makes the second press a no-op rather than restarting a round in progress.
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


## Everyone: switch to the arena, then report back. The host doesn't spawn
## anybody until every peer has said it's here -- see _arena_ready.
@rpc("authority", "call_local", "reliable")
func net_load_arena() -> void:
	round_state = RoundState.LOADING
	round_loading.emit()
	_load_arena()


## Deliberately leaves the screen black at the end rather than fading back in
## here. Bodies don't exist yet at this point -- the host only spawns them once
## every peer has reported in -- and with no local body there's no camera
## either, so fading in here would reveal an empty, un-viewed pool for however
## long the slowest peer takes to load. net_countdown() does the fade instead,
## by which time there's a body to look through.
func _load_arena() -> void:
	await Transition.fade_to_black()
	get_tree().change_scene_to_file("res://water/ocean1.tscn")
	# Wait for the Players node to genuinely exist rather than counting frames
	# and hoping. change_scene_to_file() is deferred, and reporting ready one
	# frame early means the host starts sending spawn packets at a peer whose
	# MultiplayerSpawner isn't in the tree yet -- they land with nowhere to
	# route and that peer spends the round bodiless.
	var waited := 0.0
	while _players_root() == null and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if _players_root() == null:
		push_error("net: arena never came up -- can't join the round")
		return
	# The arena (and with it Players + MultiplayerSpawner) exists now, so it's
	# safe for the host to start sending spawn packets at us.
	if is_online():
		rpc_id(1, "net_arena_ready")
	else:
		net_arena_ready()


## Host-only in practice: a peer reporting its arena is up. Once everyone has
## checked in, the host spawns the whole roster and starts the countdown.
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


## Host-only: spawn the whole roster, then set everyone counting down.
func _begin_round() -> void:
	round_state = RoundState.PLAYING
	_arena_ready.clear()
	for id in _teams.keys():
		_add_player(id)
	if is_online():
		rpc("net_countdown")
	else:
		net_countdown()


## Everyone: hold the bodies still, count in, then hand control over. Driven
## by one broadcast from the host rather than each peer starting its own clock
## when it happens to finish loading, so the counts line up across windows.
@rpc("authority", "call_local", "reliable")
func net_countdown() -> void:
	round_state = RoundState.PLAYING
	_run_countdown()


## The 3-2-1-GO! itself. Each number is one full play() of
## menu/appear_disappear_text.tscn (it holds, then spins and shrinks away),
## and nothing unlocks until the last one has finished.
func _run_countdown() -> void:
	# Lock first, fade second: the bodies exist by now, and this is the last
	# moment before the player can see them. Releasing input even for the
	# frames the fade takes would let someone with fast hands swim off before
	# the "3" has appeared.
	_set_movement_locked(true)
	await Transition.fade_from_black()
	var prompt := _ensure_countdown_text()
	for word in ["3", "2", "1", "GO!"]:
		if prompt and is_instance_valid(prompt):
			await prompt.play(word)
		else:
			await get_tree().create_timer(1.0).timeout
	_set_movement_locked(false)


## Locks or releases every body in the arena. Applied to all of them, not just
## the local one: a remote body ignores input anyway, but keeping the flag
## consistent everywhere means a peer that looks at someone else's body (the
## revive prompt does) sees the same state its owner does.
func _set_movement_locked(locked: bool) -> void:
	var players := _players_root()
	if players == null:
		return
	for p in players.get_children():
		if "movement_locked" in p:
			p.movement_locked = locked


## The countdown label, built on demand into the arena's HUD layer. Made here
## rather than baked into ocean1.tscn so the arena scene needs no edit and the
## label can't linger between rounds.
func _ensure_countdown_text() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var gui := scene.get_node_or_null("gui")
	if gui == null:
		return null
	var existing := gui.get_node_or_null("Countdown")
	if existing:
		return existing
	var prompt := COUNTDOWN_TEXT.instantiate()
	prompt.name = "Countdown"
	# No layout fixup needed here: appear_disappear_text.tscn anchors itself
	# full-rect (root AND its CenterContainer), so it centres on whatever it's
	# added to. Doing it from this side was tried and couldn't work anyway --
	# the root isn't what was mispositioned, the 40x40 CenterContainer inside
	# it was, and nothing set on the root reaches that.
	gui.add_child(prompt)
	return prompt


# ---------------------------------------------------------------------------
# Teams
# ---------------------------------------------------------------------------
## Who's on which side, peer id -> Player.Team. The host owns this outright and
## pushes the whole thing to everyone with net_sync_teams(); clients only ever
## receive it.
##
## Deliberately NOT replicated through the player body's own
## MultiplayerSynchronizer, which is where this started and where it broke.
## Two separate problems, either one fatal:
##   - A spawn-only property (spawn = true, replication_mode = NEVER) never
##     actually arrived; the client's body came up with the scene default.
##   - Making it a synced property instead is worse, not better: a client is
##     the authority on its OWN body, so it would immediately publish its own
##     default straight back over whatever the host assigned. That's the same
##     trap spawn_position() documents for `position` -- the value the host
##     sets doesn't survive contact with the owner's authority.
## Routing it through here sidesteps both: teams are roster data, the host owns
## the roster, and an RPC doesn't care who has authority over which node.
var _teams: Dictionary = {}


## This peer's idea of what side `id` is on, or -1 if it hasn't been told yet.
func team_of(id: int) -> int:
	return _teams.get(id, -1)


## Assigns (once) and returns the side a peer plays for. Host-only: reached
## only through _add_player(), which only the host runs. Idempotent, so a peer
## that respawns keeps the side it already had rather than being reshuffled.
##
## Balances by counting the roster rather than deriving from the peer id the
## way spawn_position() does -- peer ids are large random numbers, so anything
## like `id % 2` would be a coin flip per player and could happily put a whole
## four-person lobby on red.
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


## Host -> everyone, the entire team table. Sent whole rather than per-player
## so a peer that joins midway gets the sides of everyone already in the pool
## in one message, with no catch-up path to keep separately correct.
@rpc("authority", "call_local", "reliable")
func net_sync_teams(teams: Dictionary) -> void:
	_teams = teams.duplicate()
	_apply_teams_to_bodies()
	# This table is also the lobby roster (see lobby_count) -- receiving it is
	# how a client finds out anybody else is even here.
	lobby_changed.emit()


## Pushes the current table onto whatever bodies exist right now. Called both
## when the table changes (net_sync_teams) and when a body turns up after it
## (player.gd's _ready asks Net directly), so the two possible orderings --
## table first or body first -- both end up correct.
func _apply_teams_to_bodies() -> void:
	var players := _players_root()
	if players == null:
		return
	for p in players.get_children():
		var pid := String(p.name).to_int()
		if pid > 0 and _teams.has(pid) and "team" in p:
			p.team = _teams[pid]


## Host-only: hand the current table to everybody. No-op offline, where there's
## nobody to tell and the local assignment is already in place.
func _broadcast_teams() -> void:
	if not is_online() or not multiplayer.is_server():
		return
	rpc("net_sync_teams", _teams)


## Where the body belonging to `id` starts, and which way it faces.
##
## The pool's deep end and shallow end are laid out along X (ocean1.tscn puts
## `shallow` at x=-17, `transition` at x=+11.7 and `deep` at x=+20.5). Teams
## are split along Z instead -- perpendicular to that -- specifically so the
## split doesn't hand one side the deep end and the other the shallow end:
## each team's half runs the whole length of the pool, so both get half the
## deep water and half the shallow.
##
## Both peers work out the same answer for the same player without any of it
## having to survive the network, which is the point. A joining client used to
## come up at the scene's default (0, 0, 0) -- under the pool -- because the
## position the host set at spawn didn't reach it before its own physics
## started running, and being its own body's authority it then published that
## wrong position to everyone. Computing it locally means there's nothing to
## arrive late. That still holds here: the input is the team table, which is
## already synced to everyone before a round can start.
func spawn_position(id: int) -> Vector3:
	var team := team_of(id)
	if team < 0:
		# No team known (solo play, or a body spawned before the table
		# arrived) -- fall back to the old fan-around-the-centre spawn.
		var slot := absi(id) % MAX_PLAYERS
		var angle := float(slot) * TAU / float(MAX_PLAYERS)
		return _SPAWN_ORIGIN + Vector3(cos(angle), 0.0, sin(angle)) * _SPAWN_SPREAD

	# Spread teammates along X (the deep/shallow axis) and centre the row on
	# x = 0, so everyone starts an equal swim from both ends rather than one
	# unlucky teammate spawning in the deep end every time.
	var mates := _peers_on_team(team)
	var slot := maxi(mates.find(id), 0)
	var offset := (float(slot) - float(maxi(mates.size(), 1) - 1) * 0.5) * _TEAM_SPAWN_SPACING
	var z := -_TEAM_SPAWN_Z if team == PLAYER_SCRIPT.Team.RED else _TEAM_SPAWN_Z
	return Vector3(offset, _SPAWN_ORIGIN.y, z)


## Which way the body belonging to `id` faces on spawn: across the pool at the
## other team, rather than at whatever wall the scene's default rotation
## happened to point at.
func spawn_rotation_y(id: int) -> float:
	var team := team_of(id)
	if team < 0:
		return 0.0
	# Red starts on -Z looking toward +Z; blue starts on +Z looking back.
	return 0.0 if team == PLAYER_SCRIPT.Team.RED else PI


## Every peer on `team`, sorted, so "which slot am I" is the same answer on
## every machine. Sorted rather than insertion-ordered because a Dictionary's
## iteration order depends on insertion, and peers learn about each other in
## whatever order the table happened to be built in on the host.
func _peers_on_team(team: int) -> Array:
	var out := []
	for id in _teams:
		if _teams[id] == team:
			out.append(id)
	out.sort()
	return out


func _on_peer_connected(id: int) -> void:
	print("net: peer %d connected" % id)
	# A client hears about the server connecting and nothing else (ENet is
	# client/server, not a mesh), so everything below is the host's job.
	if not multiplayer.is_server():
		return
	# A lobby slot first, and only then -- if there's already a round running
	# -- a body. Assigning the side here rather than at spawn time is what
	# lets the lobby show who's on which team before anyone's in the water,
	# and it means the spawn point (which is derived from the team) is already
	# agreed on by both ends by the time the body appears.
	_assign_team(id)
	_broadcast_teams()
	if round_state == RoundState.PLAYING:
		# Joining mid-round: straight into the pool rather than being stuck
		# watching from a lobby nobody is going to press Start on again.
		_add_player(id)
	lobby_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	print("net: peer %d disconnected" % id)
	if not multiplayer.is_server():
		return
	var players := _players_root()
	if players and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
	# Drop them from the roster too, or the lobby keeps counting someone who
	# left and _assign_team keeps balancing new arrivals against a ghost.
	_teams.erase(id)
	_arena_ready.erase(id)
	_broadcast_teams()
	lobby_changed.emit()
	# They may have been the last peer the host was waiting on before it could
	# start the round -- don't hang the whole session on someone who's gone.
	if round_state == RoundState.LOADING and _everyone_ready():
		_begin_round()


func _on_connected_to_server() -> void:
	print("net: connected as peer %d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	push_error("net: connection failed")
	multiplayer.multiplayer_peer = null


func _on_server_disconnected() -> void:
	push_warning("net: host closed the game")
	leave_game()


# ---------------------------------------------------------------------------
# Menu flow orchestration
# ---------------------------------------------------------------------------
## These two exist here, not in menu.gd, for a real reason: both span a
## change_scene_to_file() call, and that FREES the node any menu.gd method
## would be running on partway through -- an `await` in menu.gd that crosses
## that boundary would be resuming a coroutine on a doomed node. Net (and
## Transition, which these lean on for the visuals) are autoloads, so they're
## still around on the other side. menu.gd just fire-and-forgets a call to
## one of these; it doesn't await either of them itself.

## Solo Play: a one-player round. Runs the exact same load -> everyone-ready
## -> spawn -> countdown path the lobby uses rather than a shortcut of its own,
## so there's one sequence to keep correct instead of two that drift apart.
## Offline, every step of that path collapses to a direct local call (see
## start_round/net_load_arena/net_arena_ready), so it costs nothing.
func start_solo_play() -> void:
	# A roster of exactly us. Cleared first so a previous session's leftovers
	# can't put phantom players in the round.
	_teams.clear()
	_arena_ready.clear()
	_assign_team(multiplayer.get_unique_id())
	round_state = RoundState.LOBBY
	start_round()


## Connect to Localhost: lands in the LOBBY either way -- joining an existing
## one if somebody's hosting, starting one if nobody is. Nobody gets a body
## until the host presses Start (see start_round).
##
## Loading the lobby scene before connecting, rather than the arena, drops the
## old scene-then-connect constraint that used to shape this: a spawn packet
## arriving before the client's MultiplayerSpawner existed was the hazard, and
## now no spawn packet can be sent at all until every peer has confirmed its
## arena is up (see net_arena_ready). The lobby genuinely doesn't need a
## Players node.
##
## Doesn't share start_connect()'s failure path on purpose: nobody hosting on
## 127.0.0.1 isn't an error, it just means nobody's started a lobby there yet
## -- so instead of bouncing back to the menu with "Couldn't connect", this
## becomes the host itself. A real remote address (F2, the CLI) keeps
## start_connect()'s honest failure instead -- silently starting your own
## lobby when a friend's real IP didn't answer would hide the actual problem
## rather than fix it.
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

	# Nobody's home. Undo whatever join_game() left behind before hosting:
	# on a hard refusal _on_connection_failed() already nulled
	# multiplayer_peer, but _await_connection_result() giving up on its own
	# 8s clock (rather than the signal ever firing) leaves the dead client
	# peer sitting there, and host_game() refuses to run while is_online()
	# still reads true because of it.
	if is_online():
		leave_game()
	Transition.show_status("Starting a lobby...")
	host_game()
	await get_tree().create_timer(0.3).timeout
	await Transition.hide_status()
	await Transition.blur_out()


## The whole "join somebody's game" flow, address and all. Split out of
## start_connect_localhost() so the --join= command line can reuse it rather
## than calling the bare join_game() and stopping there: join_game() only opens
## the connection, it doesn't get you into the session proper.
##
## Lands in the lobby, same as start_connect_localhost -- the difference
## between the two is purely what happens when nobody answers.
func start_connect(ip: String) -> void:
	await Transition.blur_in()
	Transition.show_status("Connecting...")
	get_tree().change_scene_to_file(LOBBY_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame

	var err := join_game(ip)
	# Not `err == OK and await ...` -- an explicit if instead of leaning on
	# `and`'s short-circuit to skip the await when err != OK, since an
	# await embedded inside a boolean expression is a combination worth
	# just not risking.
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


# Set while _await_connection_result() is waiting -- see there.
var _awaiting_connection := false
var _connection_succeeded := false

## Races multiplayer's own connected_to_server/connection_failed signals
## (join_game() already wires the general-purpose _on_connected_to_server/
## _on_connection_failed handlers above for logging; this is a separate,
## one-shot pair specific to a single connection attempt), with a timeout in
## case neither ever fires. Returns true on success.
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


# ---------------------------------------------------------------------------
# Debug keys -- placeholder until the real menu UI exists
# ---------------------------------------------------------------------------
## Raw keycodes rather than input actions for host/join, on purpose: these are
## temporary, and this way project.godot's input map stays clean for them.
## Delete that half once the menu calls host_game()/join_game() directly.
##
## test_lifeguard_key is different -- it's a real registered action (someone
## added it to the input map on purpose for this), so it's read the normal
## way, and it's gated by enable_lifeguard_test_key rather than being
## unconditionally live like F1/F2.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				# Opens a lobby and waits in it, same as --host. The old
				# behaviour -- opening an already-running solo game up to a
				# friend in place -- doesn't survive the lobby model: a round
				# has already started and been counted in by then, so there's
				# no lobby left to join. Guarded on is_online() so pressing it
				# twice doesn't try to host on top of a live session.
				if not is_online():
					start_host_lobby()
			KEY_F2:
				# start_connect(), not the bare join_game(): opening the
				# connection without also getting into the lobby leaves this
				# peer sitting on the menu, connected to a session it can't
				# see or start (same gap --join had). Guarded on is_online()
				# because join_game() already refuses to connect on top of a
				# live session, and without the guard start_connect() would
				# still blur and reload the scene before hitting that refusal.
				if not is_online():
					start_connect(join_ip)
	if enable_lifeguard_test_key and event.is_action_pressed("test_lifeguard_key"):
		_toggle_local_lifeguard()


## Flips is_lifeguard on whichever player body belongs to THIS peer -- for
## testing the buffs (see water/player.gd's is_lifeguard) without needing a
## real second player to fight. A toggle rather than a one-way "make me a
## lifeguard" so both states are reachable from the same key while testing.
##
## Searches the "player" group (see player.gd's _enter_tree) rather than
## assuming a fixed location, since the local player could be under a real
## gameplay scene's "Players" spawner or a hand-placed instance like
## menu.tscn's MenuPlayer, which sits outside that whole system.
func _toggle_local_lifeguard() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			p.is_lifeguard = not p.is_lifeguard
			print("net: test_lifeguard_key -> %s is_lifeguard=%s" % [p.name, p.is_lifeguard])
			return
