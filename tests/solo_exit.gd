extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(45.0).timeout.connect(func() -> void: _fail("test timed out"))
	for round_number in range(2):
		Net.start_solo_play()
		while Net._players_root() == null or Net._players_root().get_child_count() == 0:
			await get_tree().process_frame
		var player := Net._players_root().get_node("1")
		while player.movement_locked:
			await get_tree().process_frame
		_expect(player.is_multiplayer_authority(), "solo player owns its body")
		Net._handle_session_escape()
		while Net._leaving_game:
			await get_tree().process_frame
		_expect(get_tree().current_scene.scene_file_path == Net.MENU_SCENE, "escape returns to the menu")
		if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
			_fail("leaving solo restores the offline peer")
			return
		_expect(multiplayer.get_unique_id() == 1, "offline player id is valid")
		_expect(not Net.is_online(), "offline peer is not treated as online")
		var preview := get_tree().current_scene.get_node("ocean_scene/MenuPlayer")
		_expect(preview._is_local(), "menu preview authority checks remain valid")
		await get_tree().create_timer(0.5).timeout
		print("PASS solo exit round ", round_number + 1)
	Net.leave_game()
	Net.leave_game()
	_expect(multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "repeated leave keeps offline peer")
	print("PASS solo exit and replay" if not failed else "FAIL solo exit and replay")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failed = true
	push_error("FAIL " + message)
	get_tree().quit(1)
