extends Node

const SIGNAL_INTERVAL := 2.0
const CONNECT_TIMEOUT := 35.0

var peer: WebRTCMultiplayerPeer
var _code := ""
var _token := ""
var _id := 1
var _servers: Array = []
var _connections: Dictionary = {}
var _answers: Dictionary = {}
var _closed: Array = []
var _generation := 0
var _elapsed := 0.0
var _requesting := false


func available() -> bool:
	return OS.has_feature("web") or ClassDB.class_exists("WebRTCLibPeerConnection")


func start_host(code: String, token: String, servers: Array) -> void:
	if not _code.is_empty() and _code != code:
		_generation += 1
		_requesting = false
		for id: int in _connections.keys():
			if not _connections[id].finished:
				_drop_connection(id)
		_answers.clear()
		_closed.clear()
	peer = multiplayer.multiplayer_peer as WebRTCMultiplayerPeer
	_code = code
	_token = token
	_servers = servers
	_id = 1
	_elapsed = SIGNAL_INTERVAL


func start_client(session: Dictionary) -> Error:
	if not available():
		return ERR_UNAVAILABLE
	if Net.is_online() or Net._block_online_if_penalized(false):
		return ERR_ALREADY_IN_USE
	peer = WebRTCMultiplayerPeer.new()
	_id = int(session.peer_id)
	var err := peer.create_client(_id)
	if err != OK:
		return err
	_code = session.code
	_token = session.token
	_servers = session.ice_servers
	multiplayer.multiplayer_peer = peer
	var connection := _add_connection(1)
	if connection == null:
		return FAILED
	_elapsed = SIGNAL_INTERVAL
	print("net: connecting with WebRTC ...")
	return connection.create_offer()


func stop() -> void:
	_generation += 1
	if _id != 1 and not _code.is_empty():
		Matchmaking._request(HTTPClient.METHOD_POST, _client_path(), {"cancel": true}, _token)
	for state: Dictionary in _connections.values():
		state.connection.close()
	_connections.clear()
	_answers.clear()
	_closed.clear()
	peer = null
	_code = ""
	_token = ""
	_id = 1
	_requesting = false


func _add_connection(id: int) -> WebRTCPeerConnection:
	var connection := WebRTCPeerConnection.new()
	if connection.initialize({"iceServers": _servers}) != OK:
		return null
	if peer.add_peer(connection, id) != OK:
		connection.close()
		return null
	_connections[id] = {"connection": connection, "description": {}, "candidates": [],
		"sent": false, "answered": false, "age": 0.0, "finished": false}
	connection.session_description_created.connect(_description_created.bind(id))
	connection.ice_candidate_created.connect(_candidate_created.bind(id))
	return connection


func _description_created(type: String, sdp: String, id: int) -> void:
	if not _connections.has(id):
		return
	var state: Dictionary = _connections[id]
	state.description = {"type": type, "sdp": sdp}
	if state.connection.set_local_description(type, sdp) != OK:
		_drop_connection(id)


func _candidate_created(media: String, index: int, candidate: String, id: int) -> void:
	if _connections.has(id):
		_connections[id].candidates.append({"media": media, "index": index, "name": candidate})


func _apply_description(connection: WebRTCPeerConnection, description: Dictionary) -> bool:
	if connection.set_remote_description(description.type, description.sdp) != OK:
		return false
	for candidate: Dictionary in description.candidates:
		if connection.add_ice_candidate(candidate.media, int(candidate.index), candidate.name) != OK:
			return false
	return true


func _process(delta: float) -> void:
	if peer == null or _code.is_empty():
		return
	for id: int in _connections.keys():
		var state: Dictionary = _connections[id]
		var connection: WebRTCPeerConnection = state.connection
		state.age += delta
		var status := connection.get_connection_state()
		if status in [WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED]:
			_drop_connection(id)
			continue
		if peer.has_peer(id) and peer.get_peer(id).connected:
			if not state.finished:
				state.finished = true
				if _id == 1:
					_closed.append(str(id))
			continue
		if state.age > CONNECT_TIMEOUT:
			_drop_connection(id)
			continue
		# send the description and gathered candidates together
		if not state.sent and not state.description.is_empty() and connection.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			connection.poll()
			state.description["candidates"] = state.candidates.duplicate(true)
			state.sent = true
			if _id == 1:
				_answers[str(id)] = state.description
	_elapsed += delta
	if not _requesting and _elapsed >= SIGNAL_INTERVAL:
		if _id == 1:
			_poll_host()
		elif _connections.has(1) and _connections[1].sent and not _connections[1].answered:
			_poll_client()


func _drop_connection(id: int) -> void:
	if _connections.has(id):
		_connections[id].connection.close()
		_connections.erase(id)
	if peer != null and peer.has_peer(id):
		peer.remove_peer(id)
	if _id == 1 and not _closed.has(str(id)):
		_closed.append(str(id))
	_answers.erase(str(id))


func _poll_host() -> void:
	_requesting = true
	_elapsed = 0.0
	var generation := _generation
	var answers := _answers.duplicate(true)
	var closed := _closed.duplicate()
	var result: Dictionary = await Matchmaking._request(HTTPClient.METHOD_POST, "/rooms/" + _code + "/signals",
		{"answers": answers, "closed": closed}, _token)
	if generation != _generation:
		return
	_requesting = false
	if result.status != 200:
		return
	for key: String in answers:
		_answers.erase(key)
	for key: String in closed:
		_closed.erase(key)
	var offers: Dictionary = result.data.get("offers", {})
	if not offers.is_empty():
		_servers = result.data.get("ice_servers", [])
	for key: String in offers:
		var id := int(key)
		if _connections.has(id):
			continue
		if _connections.size() >= Net.MAX_PLAYERS - 1 or id < 2:
			_closed.append(key)
			continue
		var connection := _add_connection(id)
		if connection == null or not _apply_description(connection, offers[key]):
			_drop_connection(id)


func _client_path() -> String:
	return "/rooms/" + _code + "/connections/" + str(_id)


func _poll_client() -> void:
	_requesting = true
	_elapsed = 0.0
	var generation := _generation
	var result: Dictionary = await Matchmaking._request(HTTPClient.METHOD_POST, _client_path(),
		{"offer": _connections[1].description}, _token)
	if generation != _generation:
		return
	_requesting = false
	if not _connections.has(1):
		return
	if result.status in [400, 401, 404]:
		_drop_connection(1)
		return
	if result.status == 200 and result.data.get("answer") is Dictionary:
		_connections[1].answered = true
		if not _apply_description(_connections[1].connection, result.data.answer):
			_drop_connection(1)
