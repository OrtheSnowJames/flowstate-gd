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

func _ready() -> void:
	# Connected once here rather than inside host_game(): hosting twice would
	# otherwise stack duplicate connections and spawn two bodies per peer.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Launching the game without touching the network keys still has to put you
	# in the pool -- the player used to be baked into ocean1.tscn, and taking it
	# out to spawn it per-peer would otherwise leave solo play with no body at
	# all. With no peer, get_unique_id() is already 1, so this body is the same
	# one host_game() would want; hosting reuses it as-is, and only join_game()
	# has to throw it away (our id changes to whatever the host assigns).
	# Deferred because the scene tree isn't built yet during an autoload _ready.
	call_deferred("_add_player", 1)
	# Runs after the above, so hosting sees the solo body already there (and
	# no-ops on it) and joining clears it.
	call_deferred("_apply_command_line")


## Lets two instances be launched straight into a session from a terminal:
##   godot -- --host
##   godot -- --join=192.168.1.42
## purely so multiplayer can be tested without alt-tabbing to press F1/F2.
## The debug keys and join_ip still work exactly the same; delete this along
## with _unhandled_input when the menu UI lands.
##
## --host also has to actually GET the host into gameplay, not just start
## listening -- with menu.tscn as run/main_scene, "host" boots onto the menu
## same as everyone else, which has no Players node (see
## pool_scene_toggles.gd's delete_players, set on menu.tscn's ocean_scene).
## A client connecting to a host still sitting on the menu has nowhere to be
## spawned -- you can't join a game that hasn't started. start_solo_play()
## is exactly "enter gameplay", reused here rather than duplicated.
func _apply_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			host_game()
			start_solo_play()
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
	# The host plays too, so it needs a body of its own right away. Its id is 1,
	# which is exactly the body _ready already spawned for solo play, so this is
	# a no-op in the normal case -- it's here so hosting still works if that
	# body was cleared. Everyone who connects later gets one from
	# _on_peer_connected.
	_add_player(multiplayer.get_unique_id())
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
	player.position = spawn_position(id)
	# Only the host decides sides, and only the host has a roster to balance
	# against. On a client this is a no-op returning -1: its bodies get their
	# team from net_sync_teams() instead (or, if the table already arrived,
	# from player.gd's _ready asking team_of() directly).
	if multiplayer.is_server() or not is_online():
		player.team = _assign_team(id)
	players.add_child(player, true)
	# After add_child, not before: broadcasting the table is what actually gets
	# the assignment to the clients, and it has to follow the spawn packet so
	# the body it refers to already exists on the other end.
	_broadcast_teams()
	print("net: spawned player for peer %d" % id)


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


## Where the body belonging to `id` starts. Derived from the peer id rather
## than counting existing players, so every peer works out the same answer for
## the same player without any of it having to survive the network.
##
## That independence is the point. A joining client used to come up at the
## scene's default (0, 0, 0) -- under the pool -- because the position the host
## set at spawn didn't reach it before its own physics started running, and
## being its own body's authority it then published that wrong position to
## everyone. Computing it locally means there's nothing to arrive late.
func spawn_position(id: int) -> Vector3:
	# Fan out around the original single-player spawn so bodies don't overlap.
	var slot := absi(id) % MAX_PLAYERS
	var angle := float(slot) * TAU / float(MAX_PLAYERS)
	return _SPAWN_ORIGIN + Vector3(cos(angle), 0.0, sin(angle)) * _SPAWN_SPREAD


func _on_peer_connected(id: int) -> void:
	print("net: peer %d connected" % id)
	# Only the host spawns -- the MultiplayerSpawner mirrors it to everyone else.
	if multiplayer.is_server():
		_add_player(id)


func _on_peer_disconnected(id: int) -> void:
	print("net: peer %d disconnected" % id)
	if not multiplayer.is_server():
		return
	var players := _players_root()
	if players and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()


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

## Solo Play: fades out, switches to the real gameplay scene, spawns this
## peer's body there (see spawn_local_player() -- the deferred spawn-on-boot
## in _ready() only ever fires once, against whichever scene was current at
## launch), fades back in.
func start_solo_play() -> void:
	await Transition.fade_to_black()
	get_tree().change_scene_to_file("res://water/ocean1.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	spawn_local_player()
	await Transition.fade_from_black()


## Connect to Localhost: switches to the real gameplay scene FIRST -- so its
## Players/MultiplayerSpawner already exist -- and covers it immediately with
## the blur+status overlay, THEN connects. This order isn't a style choice:
## every --host/--join test this session has actually run connected a peer
## into a scene that already had its spawner; connecting first and only
## loading that scene afterward is untested and riskier -- a spawn packet the
## host sends the instant a peer connects has nowhere to route if the
## client's own MultiplayerSpawner doesn't exist yet.
##
## Doesn't share start_connect()'s failure path on purpose: nobody hosting on
## 127.0.0.1 isn't an error, it just means nobody's started a lobby there yet
## -- so instead of bouncing back to the menu with "Couldn't connect", this
## becomes the host itself. Reusing start_connect() and only branching on
## success/failure at the call site wouldn't work here -- by the time it
## returns, it's already shown "Couldn't connect", waited out that message,
## and switched back to menu.tscn (which has no Players/spawner), undoing
## exactly the state this needs to host into. A real remote address (F2, the
## CLI) keeps start_connect()'s honest failure instead -- silently starting
## your own lobby when a friend's real IP didn't answer would hide the actual
## problem rather than fix it.
func start_connect_localhost() -> void:
	await Transition.blur_in()
	Transition.show_status("Connecting...")
	get_tree().change_scene_to_file("res://water/ocean1.tscn")
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
	# Belt and suspenders, not a real second spawn: host_game() already
	# spawns peer 1's own body (our id here, since we're a fresh unconnected
	# peer), and _add_player() no-ops on a name that already exists. Calling
	# this too means this line doesn't depend on staying in sync with exactly
	# which id host_game() happens to self-spawn.
	spawn_local_player()
	await get_tree().create_timer(0.3).timeout
	await Transition.hide_status()
	await Transition.blur_out()


## The whole "join somebody's game" flow, address and all. Split out of
## start_connect_localhost() so the --join= command line can reuse it rather
## than calling the bare join_game() and stopping there: join_game() only opens
## the connection, it doesn't put you in the pool. A client left sitting on
## menu.tscn has no Players node and no MultiplayerSpawner (see
## pool_scene_toggles.gd's delete_players, set on menu.tscn's ocean_scene), so
## the host's spawn packets have nowhere to land -- exactly the same gap
## --host had before it learned to call start_solo_play().
func start_connect(ip: String) -> void:
	await Transition.blur_in()
	Transition.show_status("Connecting...")
	get_tree().change_scene_to_file("res://water/ocean1.tscn")
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
				host_game()
				# Unlike --host (which only ever fires once, at boot, before
				# any gameplay exists), F1 can be pressed interactively at any
				# time -- including mid-solo-play, to open hosting up to a
				# friend without losing where you already are. Only enter
				# gameplay if we're not already in it; a client still needs
				# somewhere to spawn, but re-triggering start_solo_play() on
				# an already-active game would fade out and reload it from
				# scratch for no reason.
				if not _is_in_gameplay():
					start_solo_play()
			KEY_F2:
				# start_connect(), not the bare join_game(): opening the
				# connection without also getting into ocean1.tscn leaves this
				# peer on the menu with nowhere for the host's spawn packets
				# to land (same gap --join had). Guarded on is_online() rather
				# than _is_in_gameplay() like F1 -- join_game() already refuses
				# to connect on top of a live session, and without the guard
				# start_connect() would still blur and reload the scene first
				# before running into that refusal.
				if not is_online():
					start_connect(join_ip)
	if enable_lifeguard_test_key and event.is_action_pressed("test_lifeguard_key"):
		_toggle_local_lifeguard()


## ocean1.tscn's root node is named "Main" -- same check this session's own
## testing has already used elsewhere to tell "in gameplay" apart from "on
## the menu" (menu.tscn's root is "Menu").
func _is_in_gameplay() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.name == "Main"


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
