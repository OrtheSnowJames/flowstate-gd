extends "res://matchmaking/rtc_transport.gd"

# negotiate the private game over the existing couch connection
var session := ""
var waiting := false
var elapsed := 0.0
var participants: Array[int] = []


func start() -> void:
	if not CouchParty.leader() or Net.is_online() or not session.is_empty():
		return
	var ids: Array[int] = []
	for id in CouchParty.members:
		ids.append(id)
	var key := Crypto.new().generate_random_bytes(16).hex_encode()
	begin.rpc(key, ids)


@rpc("authority", "call_local", "reliable")
func begin(key: String, ids: Array[int]) -> void:
	if not CouchParty.active() or Net.is_online() or not session.is_empty():
		return
	session = key
	participants = ids.duplicate()
	waiting = true
	elapsed = 0.0
	_id = multiplayer.get_unique_id()
	_servers = CouchParty.rtc._servers.duplicate(true)
	peer = WebRTCMultiplayerPeer.new()
	var error := peer.create_server(CHANNELS) if _id == 1 else peer.create_client(_id, CHANNELS)
	if error != OK:
		_failed()
		return
	Net.begin_couch_practice(peer)
	Transition.show_status("Starting room play...")
	if _id != 1:
		var connection := _add_connection(1)
		if connection == null or connection.create_offer() != OK:
			_failed()


func _process(delta: float) -> void:
	if session.is_empty():
		return
	for id: int in _connections.keys():
		var state: Dictionary = _connections[id]
		var connection: WebRTCPeerConnection = state.connection
		if connection.get_connection_state() in [WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED]:
			if waiting:
				_failed()
				return
			_drop_connection(id)
			continue
		if not state.sent and not state.description.is_empty() and connection.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			connection.poll()
			state.description.candidates = state.candidates.duplicate(true)
			state.sent = true
			description.rpc_id(id, session, state.description)
	if not waiting:
		return
	elapsed += delta
	if elapsed > CONNECT_TIMEOUT:
		_failed()
		return
	if _id != 1:
		return
	for id in participants:
		if not Net._teams.has(id) or CouchParty.members.get(id, {}).get("game_id", 0) != id:
			return
	waiting = false
	launch.rpc(session)


@rpc("any_peer", "reliable")
func description(key: String, value: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if key != session or session.is_empty() or id not in participants:
		return
	if not value.get("sdp") is String or not value.get("candidates") is Array:
		return
	if _id == 1:
		if value.get("type") != "offer" or _connections.has(id):
			return
		var connection := _add_connection(id)
		if connection == null or not _apply_description(connection, value):
			_failed()
	elif id == 1 and value.get("type") == "answer" and _connections.has(1):
		if not _apply_description(_connections[1].connection, value):
			_failed()


@rpc("authority", "call_local", "reliable")
func launch(key: String) -> void:
	if key != session or not Net.couch_practice:
		return
	waiting = false
	Net._input_blocked_by_menu = false
	await Transition.hide_status()
	if key == session and Net.couch_practice and _id == 1:
		Net.start_round()


func _failed() -> void:
	if _id == 1:
		abort.rpc(session)
	else:
		failed.rpc_id(1, session)
		abort(session)


@rpc("any_peer", "reliable")
func failed(key: String) -> void:
	if _id == 1 and key == session and multiplayer.get_remote_sender_id() in participants:
		abort.rpc(session)


@rpc("authority", "call_local", "reliable")
func abort(key: String) -> void:
	if key != session or session.is_empty():
		return
	await Net._leave_current_game_to_menu(true)
	CouchParty.message = "Couldn't start room play"
	CouchParty.open_panel()


func member_left(id: int) -> void:
	participants.erase(id)
	_drop_connection(id)


func stop() -> void:
	session = ""
	waiting = false
	participants.clear()
	super.stop()
