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

## Where join_game() connects when called with no argument. Point this at a
## real address (or read it off a UI field) to play over a network.
var join_ip := "127.0.0.1"

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
func _apply_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			host_game()
		elif arg == "--join":
			join_game()
		elif arg.begins_with("--join="):
			join_game(arg.trim_prefix("--join="))


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
	players.add_child(player, true)
	print("net: spawned player for peer %d" % id)


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
# Debug keys -- placeholder until the real menu UI exists
# ---------------------------------------------------------------------------
## Raw keycodes rather than input actions on purpose: these are temporary, and
## this way project.godot's input map stays clean. Delete this function once
## the menu calls host_game()/join_game() directly.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F1:
			host_game()
		KEY_F2:
			join_game()
