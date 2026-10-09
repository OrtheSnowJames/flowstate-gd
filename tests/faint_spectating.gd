extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(30.0).timeout.connect(func() -> void: _fail("test timed out"))
	var player := Net._players_root().get_node("1")
	player.freeze = true
	player.set_physics_process(false)
	player.position = Vector3(15, 3, 0)
	# keep the round open while testing the last conscious player
	Net._round_over = true
	player.stamina = 0.0
	player._stamina_change(0.0)
	_expect(player._unconscious, "zero stamina triggers drowning")
	await _check_spectating(player)
	_expect(Net._spectator_camera._living_lifeguard() == null, "pool view without a living lifeguard")
	player.revive()
	await get_tree().create_timer(0.3).timeout
	_expect(not Net.is_spectating() and player._camera.current, "revive restores player camera")

	Net._teams[2] = 1 - player.team
	Net._lifeguards[1 - player.team] = 2
	Net._add_player(2)
	var opponent := Net._players_root().get_node("2")
	opponent.freeze = true
	opponent.set_physics_process(false)
	Net._teams[3] = player.team
	Net._lifeguards[player.team] = 3
	Net._add_player(3)
	var lifeguard := Net._players_root().get_node("3")
	lifeguard.freeze = true
	lifeguard.set_physics_process(false)
	lifeguard.position = player._camera.global_position - player._camera.global_basis.z * 8.0 - Vector3.UP * 1.7
	player._update_nameplates()
	var plate: Control = player._nameplates[3]
	plate._process(0.0)
	_expect(plate._box.visible, "teammate name tag visible before fainting")
	player._muffled_player = null
	player.blackout_time = 0.15
	player._death()
	await _check_spectating(player)
	_expect(Net._spectator_camera._living_lifeguard() == lifeguard, "faint follows own lifeguard despite lower enemy id")
	_expect(not plate._box.visible, "name tags hidden while spectating")
	Net._round_over = false
	_expect(Net._can_watch_lifeguard(1, 3), "host allows own lifeguard")
	_expect(not Net._can_watch_lifeguard(1, 2), "host rejects enemy lifeguard")
	_expect(Net._can_watch_lifeguard(99, 2), "unteamed spectator can watch either team")
	_expect(Net.living_lifeguard(99) == opponent, "late spectator selection ignores hosts team")
	Net._round_over = true
	lifeguard._unconscious = true
	_expect(Net._spectator_camera._living_lifeguard() == null, "own lifeguard down uses pool view not enemy")
	lifeguard._unconscious = false
	player.revive()
	await get_tree().create_timer(0.3).timeout
	lifeguard.position = player._camera.global_position - player._camera.global_basis.z * 8.0 - Vector3.UP * 1.7
	plate._process(0.0)
	_expect(plate._box.visible, "name tags return after revival")

	player.blackout_time = 0.4
	player._death()
	await get_tree().create_timer(0.1).timeout
	player.revive()
	await get_tree().create_timer(0.5).timeout
	_expect(not Net.is_spectating() and player._camera.current, "revive during blackout cancels spectating")
	_expect(is_zero_approx(float(player._eyelid.material.get_shader_parameter("progress"))), "revive opens eyelids")
	print("PASS faint spectator handoff")
	get_tree().quit(1 if failed else 0)


func _check_spectating(player: Node) -> void:
	while not Net.is_spectating():
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	_expect(Net._spectator_camera.current, "spectator camera is current")
	_expect(is_zero_approx(float(player._eyelid.material.get_shader_parameter("progress"))), "blackout stays cleared after spectating")
	_expect(player._eyelid_tween == null or not player._eyelid_tween.is_running(), "eyelid closing has stopped")
	if player._muffled_player:
		_expect(not player._muffled_player.playing, "ringing stops when spectating")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failed = true
	push_error("FAIL " + message)
	get_tree().quit(1)
