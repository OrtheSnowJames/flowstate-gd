extends Node

const PROTOCOL := 2
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const HEARTBEAT_SECONDS := 10.0
const URL_FILE := "res://connect_to_url.txt"

var endpoint := ""
var busy := false
var _searching := false
var _host_token := ""
var _host_port := 0
var _generation := 0
var _elapsed := 0.0
var _updating := false
var _webrtc := false
var rtc := preload("res://matchmaking/rtc_transport.gd").new()


func _ready() -> void:
	add_child(rtc)
	endpoint = _load_endpoint()


func _load_endpoint() -> String:
	var url := OS.get_environment("FLOWSTATE_MATCHMAKING_URL").strip_edges()
	if url.is_empty() and FileAccess.file_exists(URL_FILE):
		url = FileAccess.get_file_as_string(URL_FILE).strip_edges()
	if url.is_empty():
		url = str(ProjectSettings.get_setting("matchmaking/endpoint", "")).strip_edges()
	return url.trim_suffix("/")


func configured() -> bool:
	return endpoint.begins_with("https://") or endpoint.begins_with("http://127.0.0.1:") or endpoint.begins_with("http://localhost:")


func valid_code(code: String) -> bool:
	if code.length() != 6:
		return false
	for character in code:
		if not ALPHABET.contains(character):
			return false
	return true


func quick_play() -> void:
	if not await _begin_search("Finding a match..."):
		return
	var result := await _request(HTTPClient.METHOD_POST, "/matchmaking", {"protocol": PROTOCOL})
	if result.status == 404:
		await _host_room(Net.PORT)
	elif result.status == 200:
		await _join_room(result.data)
	else:
		await _notice(result.data.get("error", "Matchmaking unavailable"))
	await _finish_search()


func join_code(code: String) -> void:
	code = code.strip_edges().to_upper()
	if not await _begin_search("Finding room..."):
		return
	if not valid_code(code):
		await _notice("Enter a valid 6 character room code")
	else:
		var result := await _request(HTTPClient.METHOD_GET, "/rooms/" + code)
		if result.status == 200:
			await _join_room(result.data)
		else:
			await _notice(result.data.get("error", "Couldn't find that room"))
	await _finish_search()


func host_match(port: int) -> void:
	if not await _begin_search("Creating room..."):
		return
	await _host_room(port, false)
	await _finish_search()


func _begin_search(message: String) -> bool:
	if busy or Net.is_online() or Net._block_online_if_penalized():
		return false
	busy = true
	_searching = true
	await Transition.blur_in()
	await Transition.show_status(message)
	if not configured():
		await _notice("Matchmaking is not configured yet")
		await _finish_search()
		return false
	return true


func _finish_search() -> void:
	await _hide_search()
	busy = false


func _hide_search() -> void:
	if not _searching:
		return
	await Transition.hide_status()
	await Transition.blur_out()
	_searching = false


func _notice(message: String) -> void:
	await Transition.show_status(message)
	await get_tree().create_timer(1.5).timeout


func _host_room(port: int, use_webrtc := true) -> void:
	await Transition.show_status("Creating room...")
	if use_webrtc and not rtc.available():
		await _notice("WebRTC extension is missing")
		return
	_webrtc = use_webrtc
	if Net.host_game(port, use_webrtc) != OK:
		await _notice("Couldn't host on port %d" % port)
		return
	_host_port = port
	var registered := await _register_room(_generation)
	if not registered:
		Net.leave_game()
		await _notice("Couldn't register room")
		return
	await _hide_search()
	await Net.open_host_lobby()


func _join_room(room: Dictionary) -> void:
	if room.get("max_players", 0) != Net.MAX_PLAYERS or (room.get("protocol", 0) != 1 and room.get("protocol", 0) != PROTOCOL):
		await _notice("Room uses a different game version")
		return
	if room.protocol == PROTOCOL:
		if not room.get("room_code") is String or not valid_code(room.room_code):
			await _notice("Invalid room code")
			return
		if not rtc.available():
			await _notice("WebRTC extension is missing")
			return
		var token := Crypto.new().generate_random_bytes(32).hex_encode()
		var result := await _request(HTTPClient.METHOD_POST, "/rooms/" + str(room.room_code) + "/connections", {}, token)
		if result.status != 201:
			await _notice(result.data.get("error", "Couldn't join room"))
			return
		var session: Dictionary = result.data
		var id = session.get("peer_id", 0)
		if (not id is float and not id is int) or int(id) != id or id < 2 or id > 2147483647 or not session.get("ice_servers") is Array:
			await _notice("Invalid connection details")
			return
		session["code"] = room.room_code
		session["token"] = token
		await _hide_search()
		await Net.start_connect("", Net.PORT, session)
		return
	var address = room.get("ip", "")
	var port = room.get("port", 0)
	var code = room.get("room_code", "")
	if not address is String or not address.is_valid_ip_address() or not port is float and not port is int:
		await _notice("Invalid room address")
		return
	if int(port) != port or port < 1 or port > 65535 or not code is String or not valid_code(code):
		await _notice("Invalid room details")
		return
	await _hide_search()
	await Net.start_connect(address, int(port))


func _register_room(generation: int) -> bool:
	var result := await _request(HTTPClient.METHOD_POST, "/rooms", {
		"port": _host_port, "players": multiplayer.get_peers().size() + 1,
		"state": _room_state(), "protocol": PROTOCOL if _webrtc else 1,
	})
	if result.status != 201:
		return false
	var code: String = str(result.data.get("room_code", ""))
	var token: String = str(result.data.get("host_token", ""))
	if not valid_code(code) or token.is_empty():
		return false
	if generation != _generation or not Net.is_online() or not multiplayer.is_server():
		_request(HTTPClient.METHOD_DELETE, "/rooms/" + code, {}, token)
		return false
	_host_token = token
	if _webrtc:
		rtc.start_host(code, token, result.data.get("ice_servers", []))
	Net.rpc("net_room_code", code)
	_elapsed = 0.0
	return true


func _room_state() -> String:
	return "lobby" if Net.round_state == Net.RoundState.LOBBY else "in_game"


func mark_dirty() -> void:
	_elapsed = HEARTBEAT_SECONDS


func _process(delta: float) -> void:
	if _host_token.is_empty() or _updating or not Net.is_online() or not multiplayer.is_server():
		return
	_elapsed += delta
	if _elapsed >= HEARTBEAT_SECONDS:
		_heartbeat()


func _heartbeat() -> void:
	_updating = true
	_elapsed = 0.0
	var generation := _generation
	var result := await _request(HTTPClient.METHOD_POST, "/rooms/" + Net.room_code + "/heartbeat", {
		"players": multiplayer.get_peers().size() + 1, "state": _room_state(),
	}, _host_token)
	if generation == _generation and result.status in [404, 409]:
		await _register_room(generation)
	_updating = false


func clear_room() -> void:
	rtc.stop()
	_generation += 1
	var token := _host_token
	var code: String = Net.room_code
	_host_token = ""
	_host_port = 0
	_elapsed = 0.0
	if not token.is_empty() and not code.is_empty():
		_request(HTTPClient.METHOD_DELETE, "/rooms/" + code, {}, token)


func _input(_event: InputEvent) -> void:
	if _searching:
		get_viewport().set_input_as_handled()


func _request(method: HTTPClient.Method, path: String, data: Dictionary = {}, token := "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	http.body_size_limit = 262144
	http.max_redirects = 0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var body := JSON.stringify(data) if method == HTTPClient.METHOD_POST else ""
	var err := http.request(endpoint + path, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"status": 0, "data": {"error": "Couldn't reach matchmaking"}}
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "data": {"error": "Couldn't reach matchmaking"}}
	var json := JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {"status": 0, "data": {"error": "Invalid matchmaking response"}}
	return {"status": response[1], "data": json.data}
