extends Node

signal changed

const AVATAR := preload("res://vr/couch_avatar.gd")
const POSES := preload("res://water/player/vr_arms.gd")
const PCM := preload("res://voice/pcm.gd")
const SPEAKER := preload("res://voice/remote_voice.gd")
const META_APP_ID := "1652096086707641"
const META_DESTINATION := "vr_room_lobby"
var code := ""
var members: Dictionary = {}
var muted := false
var busy := false
var message := ""
var lights_on := true
var group_key := ""
var rtc := preload("res://matchmaking/rtc_transport.gd").new()
var practice_game := preload("res://vr/couch_practice.gd").new()
var _api := SceneMultiplayer.new()
var _token := ""
var _generation := 0
var _heartbeat_time := 0.0
var _updating := false
var _pose_time := 0.0
var _profile_time := 0.0
var _joining_time := 0.0
var _destination: Dictionary = {}
var _avatars: Dictionary = {}
var _speakers: Dictionary = {}
var _limits: Dictionary = {}
var _poses: Dictionary = {}
var _sequence := 0
var _panel: Control
var meta_platform: Object
var _meta_ready := false
var _meta_presence: Dictionary = {}
var _meta_published: Dictionary = {}
var _meta_updating := false
var _meta_inviting := false
var _meta_retry_time := 0
var _meta_pending_code := ""
var _meta_target_code := ""


func _ready() -> void:
	_api.root_path = get_path()
	get_tree().set_multiplayer(_api, get_path())
	_api.peer_disconnected.connect(_peer_left)
	_api.connected_to_server.connect(_connected)
	_api.connection_failed.connect(func(): leave("Couldn't connect to couch room"))
	_api.server_disconnected.connect(func(): leave("Couch host left"))
	rtc.name = "Transport"
	rtc.independent = true
	rtc.max_players = 4
	add_child(rtc)
	practice_game.name = "PracticeGame"
	add_child(practice_game)
	VR.mode_changed.connect(_mode_changed)
	Net.lobby_changed.connect(_report_profile)
	changed.connect(_update_meta_presence)
	_setup_meta.call_deferred()


# setting up meta quest joining
func _setup_meta() -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton("MetaPlatformSDK"):
		return
	meta_platform = Engine.get_singleton("MetaPlatformSDK")
	meta_platform.notification_received.connect(_meta_notification)
	var request = meta_platform.initialize_platform_async(META_APP_ID)
	if request == null:
		_meta_error("Couldn't start Meta friends")
		return
	var result = await request.completed
	if result.is_error() or result.get_platform_initialize().result != 0:
		_meta_error("Couldn't start Meta friends", result)
		return
	request = meta_platform.entitlement_get_is_viewer_entitled_async()
	if request == null:
		_meta_error("Couldn't verify Meta app access")
		return
	result = await request.completed
	if result.is_error():
		_meta_error("Meta friends requires access to this app on your Meta account", result)
		return
	_meta_ready = true
	_meta_published = {"unknown": true}
	_update_meta_presence()
	_queue_meta_join(meta_platform.application_lifecycle_get_launch_details())
	changed.emit()


func broadcast_lobby_id(session_id: String) -> void:
	_meta_presence = {"code": session_id, "joinable": members.size() < 4 and not Net.couch_practice} if not session_id.is_empty() else {}
	_sync_meta_presence()


func _update_meta_presence() -> void:
	broadcast_lobby_id(code if active() and not busy else "")


func _sync_meta_presence() -> void:
	if not _meta_ready or _meta_updating or _meta_presence == _meta_published \
		or Time.get_ticks_msec() < _meta_retry_time:
		return
	_meta_updating = true
	var presence := _meta_presence.duplicate()
	var request
	if presence.is_empty():
		request = meta_platform.group_presence_clear_async()
	else:
		var options = ClassDB.instantiate("MetaPlatformSDK_GroupPresenceOptions")
		options.set_destination_api_name(META_DESTINATION)
		options.set_lobby_session_id(presence.code)
		options.set_is_joinable(presence.joinable)
		request = meta_platform.group_presence_set_async(options)
	var result = await request.completed if request != null else null
	_meta_updating = false
	if result == null or result.is_error():
		_meta_retry_time = Time.get_ticks_msec() + 10000
		_meta_error("Couldn't update Meta room presence", result)
	else:
		_meta_published = presence
		_meta_retry_time = 0
		_sync_meta_presence.call_deferred()
	changed.emit()


func can_invite_meta_friends() -> bool:
	return _meta_ready and active() and not busy and not _meta_inviting and not _meta_updating \
		and _meta_published == _meta_presence and _meta_presence.get("joinable", false)


func invite_meta_friends() -> void:
	if not can_invite_meta_friends():
		return
	_meta_inviting = true
	changed.emit()
	var options = ClassDB.instantiate("MetaPlatformSDK_InviteOptions")
	var request = meta_platform.group_presence_launch_invite_panel_async(options)
	var result = await request.completed if request != null else null
	_meta_inviting = false
	if result == null or result.is_error():
		_meta_error("Couldn't open Meta friend invites", result)
	changed.emit()


func _meta_notification(notification: Object) -> void:
	if notification.is_error():
		return
	var kind: int = notification.type
	if kind == ClassDB.class_get_integer_constant("MetaPlatformSDK", "MESSAGE_NOTIFICATION_GROUP_PRESENCE_JOIN_INTENT_RECEIVED"):
		_queue_meta_join(notification.get_group_presence_join_intent())
	elif kind == ClassDB.class_get_integer_constant("MetaPlatformSDK", "MESSAGE_NOTIFICATION_APPLICATION_LIFECYCLE_LAUNCH_INTENT_CHANGED"):
		_queue_meta_join(meta_platform.application_lifecycle_get_launch_details())
	elif kind == ClassDB.class_get_integer_constant("MetaPlatformSDK", "MESSAGE_NOTIFICATION_GROUP_PRESENCE_LEAVE_INTENT_RECEIVED"):
		var details = notification.get_group_presence_leave_intent()
		if details != null and details.destination_api_name == META_DESTINATION and details.lobby_session_id == code:
			leave()


func _queue_meta_join(details) -> void:
	if details == null or details.destination_api_name != META_DESTINATION:
		return
	var value: String = str(details.lobby_session_id).strip_edges().to_upper()
	if not Matchmaking.valid_code(value):
		_meta_error("This Meta invite doesn't contain a valid couch room")
		return
	if value == code or value == _meta_pending_code or value == _meta_target_code:
		return
	_meta_pending_code = value


func _join_meta_room() -> void:
	_meta_target_code = _meta_pending_code
	_meta_pending_code = ""
	busy = true
	message = "Joining friend's couch room..."
	changed.emit()
	var generation := _generation
	var prepared := await _prepare_meta_join(generation)
	if generation == _generation:
		if prepared:
			var value := _meta_target_code
			leave()
			open_panel()
			await join_room(value)
		else:
			busy = false
			message = ""
			changed.emit()
	_meta_target_code = ""


func _prepare_meta_join(generation: int) -> bool:
	if Net.is_online() and not Net.couch_practice and not Net._is_online_session_alone():
		await Net._confirm_online_disconnect()
		if generation != _generation or Net.is_online():
			return false
	if VR.immersive:
		busy = false
		await VR.exit_immersive()
		if generation != _generation or not available():
			return false
		busy = true
	if Net.is_online() or Net._escape_scene_active():
		await Net._leave_current_game_to_menu(true)
	return generation == _generation and available()


func _meta_error(text: String, result = null) -> void:
	if result != null and result.is_error():
		push_warning(text + ": " + str(result.error.message))
	else:
		push_warning(text)
	if not busy:
		message = text
		changed.emit()


func available() -> bool:
	return VR.active and not VR.immersive and not VR.entering and not VR.exiting


func active() -> bool:
	return not code.is_empty() and not members.is_empty() and available()


func leader() -> bool:
	return active() and _api.is_server()


func party_size() -> int:
	return maxi(1, members.size()) if active() else 1


func can_use_screen() -> bool:
	return not active() or leader() or is_instance_valid(_panel) \
		or Net._connection_game_in_progress \
		or _guest_menu_visible() \
		or (Net.round_state == Net.RoundState.PLAYING and Net._round_started and not Net._round_over)


func _guest_menu_visible() -> bool:
	return get_tree().get_nodes_in_group("couch_guest_menu").any(func(menu): return menu.is_visible_in_tree())


func ready_for_match() -> bool:
	if not active():
		return true
	for member in members.values():
		if member.game_id <= 0 or not Net._teams.has(member.game_id):
			return false
	return true


func open_panel() -> void:
	if not available() or is_instance_valid(_panel):
		return
	_panel = load("res://vr/couch_panel.tscn").instantiate()
	Transition.add_child(_panel)


func create_room() -> void:
	if not available() or busy or not code.is_empty():
		return
	if not Matchmaking.configured() or not rtc.available():
		message = "Matchmaking or WebRTC unavailable"
		changed.emit()
		return
	busy = true
	message = "Creating couch room..."
	changed.emit()
	var generation := _generation
	var result: Dictionary = await Matchmaking._request(HTTPClient.METHOD_POST, "/rooms",
		{"port": Net.PORT, "protocol": 2, "room_type": "couch", "players": 1})
	if generation != _generation:
		if result.status == 201:
			Matchmaking._request(HTTPClient.METHOD_DELETE, "/rooms/" + str(result.data.room_code), {}, str(result.data.host_token))
		return
	busy = false
	if result.status != 201 or result.data.get("room_type") != "couch":
		message = result.data.get("error", "Update the matchmaking Lambda for couch rooms")
		if result.status == 201:
			Matchmaking._request(HTTPClient.METHOD_DELETE, "/rooms/" + str(result.data.room_code), {}, str(result.data.host_token))
		changed.emit()
		return
	var peer := WebRTCMultiplayerPeer.new()
	if peer.create_server(rtc.CHANNELS) != OK:
		Matchmaking._request(HTTPClient.METHOD_DELETE, "/rooms/" + str(result.data.room_code), {}, str(result.data.host_token))
		leave("Couldn't create couch connection")
		return
	_api.multiplayer_peer = peer
	code = result.data.room_code
	_token = result.data.host_token
	group_key = Crypto.new().generate_random_bytes(32).hex_encode()
	members = {1: {"seat": 0, "name": _name(), "team": -1, "game_id": 0}}
	lights_on = VR._room_root.lights_on
	muted = false
	rtc.start_host(code, _token, result.data.get("ice_servers", []))
	message = ""
	_refresh()
	if Net.is_online() and not Net.room_code.is_empty():
		follow_match({"code": Net.room_code})


func join_room(value: String) -> void:
	if not available() or busy or not code.is_empty():
		return
	value = value.strip_edges().to_upper()
	if not Matchmaking.valid_code(value):
		message = "Enter a valid 6 character code"
		changed.emit()
		return
	busy = true
	message = "Joining couch room..."
	changed.emit()
	var generation := _generation
	var result: Dictionary = await Matchmaking._request(HTTPClient.METHOD_GET, "/rooms/" + value)
	if generation != _generation:
		return
	if result.status != 200 or result.data.get("room_type") != "couch":
		busy = false
		message = result.data.get("error", "That code is not a couch room")
		changed.emit()
		return
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	result = await Matchmaking._request(HTTPClient.METHOD_POST, "/rooms/" + value + "/connections", {}, token)
	if generation != _generation:
		if result.status == 201 and result.data.has("peer_id"):
			Matchmaking._request(HTTPClient.METHOD_POST, "/rooms/" + value + "/connections/" + str(result.data.peer_id), {"cancel": true}, token)
		return
	if result.status != 201:
		busy = false
		message = result.data.get("error", "Couldn't join couch room")
		changed.emit()
		return
	code = value
	muted = false
	var session: Dictionary = result.data
	session.code = code
	session.token = token
	_joining_time = 0.0
	if rtc.start_client(session) != OK:
		leave("Couldn't connect to couch room")


func leave(reason := "") -> void:
	if Net.couch_practice:
		Net._leave_current_game_to_menu(true)
	_generation += 1
	_meta_pending_code = ""
	var old_code := code
	var old_token := _token
	code = ""
	_token = ""
	members.clear()
	group_key = ""
	_destination.clear()
	rtc.stop()
	if _api.multiplayer_peer:
		_api.multiplayer_peer.close()
	_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	for avatar in _avatars.values():
		if is_instance_valid(avatar):
			avatar.queue_free()
	_avatars.clear()
	for speaker in _speakers.values():
		if is_instance_valid(speaker):
			speaker.queue_free()
	_speakers.clear()
	if is_instance_valid(VR._room_root):
		VR._room_root.remove_meta("party_seat")
	_poses.clear()
	_limits.clear()
	_sequence = 0
	busy = false
	_updating = false
	message = reason
	if not old_token.is_empty():
		Matchmaking._request(HTTPClient.METHOD_DELETE, "/rooms/" + old_code, {}, old_token)
	VR._request_room_center()
	changed.emit()


func _mode_changed() -> void:
	if not available() and is_instance_valid(_panel):
		_panel.queue_free()
	if not available() and (not code.is_empty() or busy):
		leave()


func _name() -> String:
	return Settings.player_name.left(32) if not Settings.player_name.is_empty() else "Player"


func _connected() -> void:
	rpc_id(1, "hello", _name())


@rpc("any_peer", "reliable")
func hello(display_name: String) -> void:
	if not leader():
		return
	var id := _api.get_remote_sender_id()
	if id not in _api.get_peers() or members.has(id):
		return
	if members.size() >= 4:
		_api.multiplayer_peer.disconnect_peer(id)
		return
	var occupied := []
	for member in members.values():
		occupied.append(member.seat)
	for seat in range(4):
		if seat not in occupied:
			members[id] = {"seat": seat, "name": display_name.strip_edges().left(32), "team": -1, "game_id": 0}
			break
	_publish()
	if not _destination.is_empty():
		rpc_id(id, "join_match", _destination)


func _peer_left(id: int) -> void:
	if leader():
		practice_game.member_left(id)
		members.erase(id)
		_publish.call_deferred()


func _publish() -> void:
	if not leader():
		return
	room_state(code, group_key, members, lights_on)
	for peer in _peers():
		rpc_id(peer, "room_state", code, group_key, members, lights_on)
	_heartbeat_time = 10.0


func _peers() -> Array[int]:
	var result: Array[int] = []
	for id in _api.get_peers():
		var state: Dictionary = rtc._connections.get(id, {})
		if state.has("connection") and state.connection.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED:
			result.append(id)
	return result


@rpc("authority", "call_local", "reliable")
func room_state(room_code: String, key: String, roster: Dictionary, lighting: bool) -> void:
	code = room_code
	group_key = key
	members = roster.duplicate(true)
	lights_on = lighting
	busy = false
	message = ""
	_refresh()


func _refresh() -> void:
	if not available():
		return
	for id in _avatars.keys():
		if not members.has(id):
			if is_instance_valid(_avatars[id]):
				_avatars[id].queue_free()
			_avatars.erase(id)
			_poses.erase(id)
			if is_instance_valid(_speakers.get(id)):
				_speakers[id].queue_free()
			_speakers.erase(id)
	for id in members:
		if not is_instance_valid(_avatars.get(id)):
			var avatar := AVATAR.new()
			VR._room_root.add_child(avatar)
			_avatars[id] = avatar
		var member: Dictionary = members[id]
		_avatars[id].setup(seat_transform(member.seat), member.team, id == _api.get_unique_id())
	VR._room_root.lights_on = lights_on
	VR._room_root.apply_lighting()
	var seat := local_seat()
	if VR._room_root.get_meta("party_seat", -1) != seat:
		VR._room_root.set_meta("party_seat", seat)
		VR._request_room_center()
	register_team()
	changed.emit()


func seat_transform(seat: int) -> Transform3D:
	return VR._room_root.get_node("PartySeats/Seat%d" % clampi(seat, 0, 3)).global_transform.orthonormalized()


func local_seat() -> int:
	return int(members.get(_api.get_unique_id(), {}).get("seat", 0)) if active() else 0


func toggle_lights() -> void:
	if leader():
		lights_on = not lights_on
		_publish()


func _process(delta: float) -> void:
	if _meta_ready:
		if _meta_retry_time > 0:
			_sync_meta_presence()
		if not _meta_pending_code.is_empty() and _meta_target_code.is_empty() and not busy \
			and VR.active and not VR.entering and not VR.exiting \
			and not Net._leaving_game and not Net._escape_menu_open and not Matchmaking.busy:
			_join_meta_room()
	if not code.is_empty() and busy and _meta_target_code.is_empty():
		_joining_time += delta
		if _joining_time > 40.0:
			leave("Couch connection timed out")
	if not active():
		return
	_heartbeat_time += delta
	_profile_time += delta
	_pose_time += delta
	if leader() and _heartbeat_time >= 10.0 and not _updating:
		_heartbeat()
	if _profile_time >= 0.5:
		_profile_time = 0.0
		_report_profile()
	if _pose_time >= 0.05:
		_pose_time = 0.0
		var pose := local_pose()
		if leader():
			_poses[1] = pose
		else:
			rpc_id(1, "upload_pose", pose)
		if leader():
			poses(_poses)
			for peer in _peers():
				rpc_id(peer, "poses", _poses)
	var local := _api.get_unique_id()
	if is_instance_valid(_avatars.get(local)):
		_avatars[local].apply_pose(local_pose(), 0.0)


func local_pose() -> Array:
	var inverse := seat_transform(local_seat()).affine_inverse()
	var pose: Array = [inverse * VR._head.global_transform, Transform3D.IDENTITY, Transform3D.IDENTITY, 0]
	for i in range(VR._hands.size()):
		if VR._hands[i].get_is_active():
			pose[i + 1] = (inverse * POSES.hand_tip_transform(VR._hands[i], VR._origin)).orthonormalized()
			pose[3] |= 1 << i
	return pose if POSES.valid_pose(pose) else []


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func upload_pose(pose: Array) -> void:
	var id := _api.get_remote_sender_id()
	if leader() and members.has(id) and POSES.valid_pose(pose):
		_poses[id] = pose


@rpc("authority", "call_local", "unreliable_ordered", 1)
func poses(values: Dictionary) -> void:
	for id in values:
		if id != _api.get_unique_id() and is_instance_valid(_avatars.get(id)) and values[id] is Array and POSES.valid_pose(values[id]):
			_avatars[id].apply_pose(values[id], 0.05)


func _heartbeat() -> void:
	_updating = true
	_heartbeat_time = 0.0
	var generation := _generation
	var result: Dictionary = await Matchmaking._request(HTTPClient.METHOD_POST, "/rooms/" + code + "/heartbeat",
		{"players": members.size(), "state": "couch"}, _token)
	if generation != _generation:
		return
	_updating = false
	if result.status in [401, 404, 409]:
		leave("Couch room expired")


func _report_profile() -> void:
	_update_meta_presence()
	if not active():
		return
	var game_id := get_tree().get_multiplayer().get_unique_id() if Net.is_online() else 0
	if leader() and game_id == 0:
		_destination.clear()
	var team := Net.team_of(game_id) if game_id > 0 else -1
	var current: Dictionary = members.get(_api.get_unique_id(), {})
	if current.get("team", -1) == team and current.get("game_id", 0) == game_id and current.get("name", "") == _name():
		return
	if leader():
		_set_profile(1, team, game_id, _name())
	else:
		rpc_id(1, "profile", team, game_id, _name())


@rpc("any_peer", "reliable")
func profile(team: int, game_id: int, display_name: String) -> void:
	if leader():
		_set_profile(_api.get_remote_sender_id(), team, game_id, display_name)


func _set_profile(id: int, team: int, game_id: int, display_name: String) -> void:
	if not members.has(id) or team not in [-1, 0, 1] or game_id < 0:
		return
	members[id].team = team
	members[id].game_id = game_id
	members[id].name = display_name.left(32)
	_publish()


func follow_match(destination: Dictionary) -> void:
	if not leader():
		return
	_destination = destination.duplicate()
	register_team()
	for peer in _peers():
		rpc_id(peer, "join_match", _destination)


@rpc("authority", "reliable")
func join_match(destination: Dictionary) -> void:
	if not active() or leader() or Net.is_online() or Matchmaking.busy:
		return
	if not str(destination.get("code", "")).is_empty():
		await Matchmaking.join_code(destination.code)
	else:
		await Net.start_connect(str(destination.get("ip", "")), int(destination.get("port", Net.PORT)))


func register_team() -> void:
	if not active() or not Net.is_online() or Net.couch_practice:
		return
	if Net.multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if get_tree().get_multiplayer().is_server():
		Net.assign_party(1, group_key, party_size())
	else:
		Net.rpc_id(1, "net_join_party", group_key, party_size())


func send_voice(data: PackedByteArray) -> void:
	if not active() or muted:
		return
	_sequence += 1
	if leader():
		_relay_voice(1, _sequence, data)
	else:
		rpc_id(1, "upload_voice", _sequence, data)


@rpc("any_peer", "call_remote", "unreliable", 2)
func upload_voice(sequence: int, data: PackedByteArray) -> void:
	var id := _api.get_remote_sender_id()
	if leader() and members.has(id) and _accept_voice(id, sequence, data):
		_relay_voice(id, sequence, data)


func _accept_voice(id: int, sequence: int, data: PackedByteArray) -> bool:
	if data.size() != PCM.BYTES or sequence < 0:
		return false
	var now := Time.get_ticks_msec()
	var limit: Dictionary = _limits.get(id, {"sequence": -1, "tokens": 10.0, "time": now})
	limit.tokens = minf(10.0, limit.tokens + (now - limit.time) * 0.06)
	limit.time = now
	_limits[id] = limit
	if sequence <= limit.sequence or limit.tokens < 1.0:
		return false
	limit.sequence = sequence
	limit.tokens -= 1.0
	return true


func _relay_voice(id: int, sequence: int, data: PackedByteArray) -> void:
	_receive_voice(id, sequence, data)
	for peer in _peers():
		if peer != 1 and peer != id:
			rpc_id(peer, "voice", id, sequence, data)


@rpc("authority", "call_remote", "unreliable", 2)
func voice(id: int, sequence: int, data: PackedByteArray) -> void:
	if members.has(id) and _accept_voice(id, sequence, data):
		_receive_voice(id, sequence, data)


func _receive_voice(id: int, sequence: int, data: PackedByteArray) -> void:
	if not active() or id == _api.get_unique_id() or not is_instance_valid(_avatars.get(id)):
		return
	var speaker = _speakers.get(id)
	if not is_instance_valid(speaker) or speaker.is_queued_for_deletion():
		speaker = SPEAKER.new()
		add_child(speaker)
		speaker.spatial_at(_avatars[id].voice_origin)
		_speakers[id] = speaker
	speaker.receive(sequence, data)


func _input(event: InputEvent) -> void:
	if event.is_action("voice_toggle"):
		return
	if not active() or leader():
		return
	if _guest_menu_visible() and not is_instance_valid(_panel) and event.is_action_pressed("ui_cancel"):
		open_panel()
		get_viewport().set_input_as_handled()
		return
	if can_use_screen():
		return
	if event.is_action_pressed("ui_cancel"):
		open_panel()
	get_viewport().set_input_as_handled()
