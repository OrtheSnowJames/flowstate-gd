extends Node

const PCM := preload("res://voice/pcm.gd")
const REMOTE_VOICE := preload("res://voice/remote_voice.gd")
const BUS := "VoiceCapture"
const PERMISSION := "android.permission.RECORD_AUDIO"
const MIC_ICON := preload("res://voice/mic.svg")

var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _speakers := {}
var _limits := {}
var _sequence := 0
var _speech_tail := 0
var _permission_pending := false
var _permission_requested := false
var _session: MultiplayerPeer
var _device_check := 0.0
var _error := ""
var _status: Label
var _prompt: Control
var _local_speaking_until := 0
var _talkers: VBoxContainer
var _talker_ids: Array[int] = []


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_remove_peer)
	Net.lobby_changed.connect(_roster_changed)
	get_tree().on_request_permissions_result.connect(_permission_result)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.offset_left = -300
	_status.offset_top = 16
	_status.offset_right = -16
	_status.offset_bottom = 60
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 4)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status)
	_status.hide()
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 1.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 0.6
	scroll.offset_left = -300
	scroll.offset_right = -16
	scroll.offset_top = 64
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(scroll)
	_talkers = VBoxContainer.new()
	_talkers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_talkers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_talkers)


func connected() -> bool:
	return Net.is_online() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func listening() -> bool:
	return connected() and Settings.voice_configured and Settings.voice_enabled


func same_team(first: int, second: int) -> bool:
	var team := Net.team_of(first)
	return team >= 0 and team == Net.team_of(second)


func is_speaking(id: int) -> bool:
	if not listening() or not same_team(id, multiplayer.get_unique_id()):
		return false
	if id == multiplayer.get_unique_id():
		return Time.get_ticks_msec() < _local_speaking_until
	var speaker = _speakers.get(id)
	return is_instance_valid(speaker) and not speaker.is_queued_for_deletion() and Time.get_ticks_msec() < speaker.speaking_until


func _roster_changed() -> void:
	if connected():
		for id in _speakers.keys():
			if not same_team(id, multiplayer.get_unique_id()):
				_remove_peer(id)
	_talker_ids.clear()
	_update_talkers()


func _update_talkers() -> void:
	if _talkers == null:
		return
	var active: Array[int] = []
	if connected():
		for id: int in Net._teams:
			if is_speaking(id):
				active.append(id)
	active.sort()
	_talkers.visible = _status.visible
	if active == _talker_ids and _talkers.get_child_count() == active.size():
		return
	_talker_ids = active
	for child in _talkers.get_children():
		_talkers.remove_child(child)
		child.queue_free()
	for id in active:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = Net.name_of(id)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		row.add_child(label)
		var icon := TextureRect.new()
		icon.texture = MIC_ICON
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(0.5, 1.0, 0.65)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		_talkers.add_child(row)


func prompt_setup(parent: Node) -> void:
	if Settings.voice_configured and not Settings.player_name.is_empty():
		return
	if is_instance_valid(_prompt):
		return
	_prompt = load("res://menu/name_prompt.tscn").instantiate()
	parent.add_child(_prompt)
	_prompt.open(Settings.player_name, "Enter your name", _profile_chosen)


func _profile_chosen(new_name: String) -> void:
	Settings.player_name = new_name
	Settings.save_settings()
	Net.update_my_name()


func apply_settings() -> void:
	_stop_capture()
	_clear_speakers()
	_update_talkers()
	_error = ""
	_permission_requested = false
	_device_check = 0.0
	Settings.save_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not connected() or event.is_echo() or not event.is_action_pressed("voice_toggle"):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit or Net.input_blocked_by_menu():
		return
	if not get_tree().get_nodes_in_group("controller_modal").is_empty():
		return
	get_viewport().set_input_as_handled()
	if not Settings.voice_configured:
		prompt_setup(Transition)
		return
	Settings.voice_enabled = not Settings.voice_enabled
	apply_settings()


func _process(delta: float) -> void:
	if not connected():
		if _session != null:
			reset_session()
		_status.hide()
		_update_talkers()
		return
	if _session != multiplayer.multiplayer_peer:
		reset_session(false)
		_session = multiplayer.multiplayer_peer
	_status.visible = get_tree().get_nodes_in_group("controller_modal").is_empty()
	_status.text = "VC: " + ("On" if listening() else "Off")
	if not _error.is_empty():
		_status.text = "VC: " + _error
	_status.modulate = Color(0.5, 1.0, 0.65) if listening() and _error.is_empty() else Color(1.0, 0.7, 0.6)
	_update_talkers()
	if not listening():
		_stop_capture()
		_clear_speakers()
		return
	_device_check -= delta
	if _device_check <= 0.0:
		_device_check = 2.0
		_update_microphone()
	if _mic != null and _mic.playing:
		_capture_packets()


func _update_microphone() -> void:
	if OS.has_feature("android") and not OS.get_granted_permissions().has(PERMISSION):
		if not _permission_pending and not _permission_requested:
			_permission_requested = true
			_permission_pending = not OS.request_permission(PERMISSION)
		_error = "Waiting for mic permission"
		return
	var devices := AudioServer.get_input_device_list()
	if not devices.has(Settings.voice_device):
		_stop_capture()
		_error = "Selected mic unavailable"
		return
	if _mic != null and _mic.playing:
		return
	_error = ""
	if _mic == null:
		_create_capture()
	AudioServer.input_device = Settings.voice_device
	_capture.clear_buffer()
	_mic.play()
	if not _mic.playing:
		_error = "Microphone unavailable"


func _permission_result(permission: String, granted: bool) -> void:
	if permission != PERMISSION:
		return
	_permission_pending = false
	_device_check = 0.0
	if not granted:
		Settings.voice_enabled = false
		Settings.save_settings()
		_stop_capture()
		_error = "Mic permission denied"
	else:
		_error = ""


func _create_capture() -> void:
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	var low_pass := AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = 7000.0
	AudioServer.add_bus_effect(index, low_pass)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.2
	AudioServer.add_bus_effect(index, _capture)
	# capture before muting so your microphone never echoes locally
	AudioServer.set_bus_mute(index, true)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = BUS
	add_child(_mic)


func _capture_packets() -> void:
	var frames := int(AudioServer.get_mix_rate() * 0.02)
	if _capture.get_frames_available() > frames * 5:
		_capture.clear_buffer()
		return
	while _capture.can_get_buffer(frames):
		var samples := _capture.get_buffer(frames)
		var energy := 0.0
		for sample in samples:
			energy += sample.length_squared() * 0.5
		if sqrt(energy / samples.size()) >= 0.002:
			_speech_tail = 10
			_local_speaking_until = Time.get_ticks_msec() + 300
		if _speech_tail <= 0:
			continue
		_speech_tail -= 1
		_send_packet(PCM.encode(samples))


func _send_packet(data: PackedByteArray) -> void:
	if not listening():
		return
	_sequence += 1
	if multiplayer.is_server():
		_relay(1, _sequence, data)
	else:
		upload.rpc_id(1, _sequence, data)


@rpc("any_peer", "call_remote", "unreliable", 2)
func upload(sequence: int, data: PackedByteArray) -> void:
	if not connected() or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender not in multiplayer.get_peers() or not _accept_packet(sender, sequence, data):
		return
	_relay(sender, sequence, data)


func _relay(sender: int, sequence: int, data: PackedByteArray) -> void:
	_receive(sender, sequence, data)
	for peer in multiplayer.get_peers():
		if peer != sender and same_team(sender, peer):
			deliver.rpc_id(peer, sender, sequence, data)


@rpc("authority", "call_remote", "unreliable", 2)
func deliver(sender: int, sequence: int, data: PackedByteArray) -> void:
	if not connected() or multiplayer.get_remote_sender_id() != 1:
		return
	if sender != 1 and sender not in multiplayer.get_peers():
		return
	if _accept_packet(sender, sequence, data):
		_receive(sender, sequence, data)


func _accept_packet(sender: int, sequence: int, data: PackedByteArray) -> bool:
	if sequence < 0 or sequence > 2147483647 or data.size() != PCM.BYTES:
		return false
	var now := Time.get_ticks_msec()
	var limit: Dictionary = _limits.get(sender, {"time": now, "tokens": 10.0, "sequence": -1})
	limit.tokens = minf(10.0, limit.tokens + (now - limit.time) * 0.06)
	limit.time = now
	_limits[sender] = limit
	if limit.tokens < 1.0 or sequence <= limit.sequence:
		return false
	limit.tokens -= 1.0
	limit.sequence = sequence
	return true


func _receive(sender: int, sequence: int, data: PackedByteArray) -> void:
	if not listening() or sender == multiplayer.get_unique_id() or not same_team(sender, multiplayer.get_unique_id()):
		return
	var speaker = _speakers.get(sender)
	if not is_instance_valid(speaker) or speaker.is_queued_for_deletion():
		speaker = REMOTE_VOICE.new()
		speaker.name = "Speaker%d" % sender
		add_child(speaker)
		_speakers[sender] = speaker
	speaker.receive(sequence, data)


func _stop_capture() -> void:
	if _mic != null:
		_mic.stop()
	if _capture != null:
		_capture.clear_buffer()
	_speech_tail = 0
	_local_speaking_until = 0


func _clear_speakers() -> void:
	for speaker in _speakers.values():
		if is_instance_valid(speaker):
			speaker.stop()
			speaker.queue_free()
	_speakers.clear()


func _remove_peer(id: int) -> void:
	var speaker = _speakers.get(id)
	if is_instance_valid(speaker):
		speaker.stop()
		speaker.queue_free()
	_speakers.erase(id)
	_limits.erase(id)


func reset_session(close_prompt := true) -> void:
	if close_prompt and is_instance_valid(_prompt):
		_prompt.queue_free()
	_stop_capture()
	_clear_speakers()
	_limits.clear()
	_sequence = 0
	_session = null
	_error = ""
	_device_check = 0.0
	_status.hide()
	_update_talkers()
