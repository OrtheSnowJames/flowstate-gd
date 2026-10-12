extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(45.0).timeout.connect(func() -> void: get_tree().quit(1))
	Settings.player_name = "Cube Test"
	get_tree().change_scene_to_file(Net.MENU_SCENE)
	await get_tree().create_timer(0.6).timeout
	_choose_mode(-1)
	await Net.start_host_lobby(18093)
	_expect(not Net.is_online(), "cancel does not create a room")
	_expect(get_tree().current_scene.scene_file_path == Net.MENU_SCENE, "cancel stays in menu")
	_choose_mode(Net.GameMode.KING_OF_CUBE)
	await Net.start_host_lobby(18093)
	_expect(Net.is_online() and Net.game_mode == Net.GameMode.KING_OF_CUBE, "host creates selected mode")
	_expect(get_tree().current_scene.get_node("UI/Count").text.contains("King of the Cube"), "lobby displays mode")
	Net.leave_game()
	_expect(Net.game_mode == Net.GameMode.NORMAL, "leaving resets mode")
	_choose_mode(Net.GameMode.NORMAL)
	await Net.start_host_lobby(18093)
	_expect(Net.is_online() and Net.game_mode == Net.GameMode.NORMAL, "normal room can still be created")
	Net.leave_game()
	get_tree().change_scene_to_file("res://water/ocean1.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	Net.round_state = Net.RoundState.PLAYING
	Net._round_over = false
	Net._round_started = true
	Net._teams = {1: 0, 2: 1, 3: 0}
	for id in Net._teams:
		Net._add_player(id)
	var scene := get_tree().current_scene
	var cube: RigidBody3D = scene.get_node("PushCube")
	var controller := cube.get_node("KingOfCube")
	controller.set_physics_process(false)
	cube.freeze = true
	cube.position = Vector3(12, 10, 0)
	cube.rotation = Vector3.ZERO
	var players := Net._players_root()
	var red := players.get_node("1")
	var blue := players.get_node("2")
	var teammate := players.get_node("3")
	for player in players.get_children():
		player.freeze = true
		player.set_physics_process(false)
		player.position = Vector3(-15, 20, 0)
	var original: Material = cube.get_node("MeshInstance3D").material_override
	Net.net_sync_game_mode(Net.GameMode.KING_OF_CUBE)
	Net._reset_round_scoreboard()
	_expect(Net._round_red_goal == 100 and Net._round_blue_goal == 100, "both goals are 100")
	_expect(scene.get_node("Scoreboard").red_goal.text == "Goal: 100 points", "original scoreboard shows goal")
	await _tick(controller, 2.0)
	_expect(Net.cube_control == Net.CubeControl.NEUTRAL and Net._round_red_score == 0, "empty cube is neutral without scoring")
	_expect(controller._material.albedo_color == controller.COLORS[0], "neutral cube is gold")
	await _capture_cube(cube, "gold")
	red.position = Vector3(12, 11.82, 0)
	Net._round_started = false
	await _tick(controller, 2.0)
	_expect(Net._round_red_score == 0, "countdown cannot score")
	Net._round_started = true
	await _tick(controller, 0.5)
	_expect(Net.cube_control == Net.CubeControl.RED and Net._round_red_score == 0, "red controls cube before first point")
	await _tick(controller, 0.5)
	_expect(Net._round_red_score == 1, "one point per second")
	await _capture_cube(cube, "red")
	teammate.position = Vector3(12.5, 11.82, 0)
	await _tick(controller, 2.0)
	_expect(Net._round_red_score == 3, "teammates do not multiply points")
	blue.position = Vector3(11.5, 11.82, 0)
	await _tick(controller, 3.0)
	_expect(Net.cube_control == Net.CubeControl.CONTESTED, "both teams turn cube purple")
	_expect(Net._round_red_score == 3 and Net._round_blue_score == 0, "contested cube pauses scoring")
	await _capture_cube(cube, "purple")
	red.position = Vector3(14, 11.82, 0)
	teammate.position = Vector3(12, 15, 0)
	await _tick(controller, 1.0)
	_expect(Net.cube_control == Net.CubeControl.BLUE and Net._round_blue_score == 1, "nearby and airborne players do not contest")
	await _capture_cube(cube, "blue")
	blue._unconscious = true
	Net.on_player_down()
	await _tick(controller, 1.0)
	_expect(Net.cube_control == Net.CubeControl.NEUTRAL, "fainted players do not hold the cube")
	_expect(not Net._round_over and Net._round_red_score == 3, "faints do not score or end cube rounds")
	controller._update_respawns(players, 4.1)
	_expect(not blue._unconscious and blue.position.is_equal_approx(Net.spawn_position(2)), "fainted players respawn at their team spawn")
	_expect(blue.stamina == blue.max_stamina, "respawn restores stamina")
	for player in [red, blue]:
		player._unconscious = true
		player.stamina = 0.0
		player.momentum = 7.0
		player.position = Vector3(0, 7, 11 if player == red else -11)
	controller._update_respawns(players, 4.0)
	_expect(red._unconscious and blue._unconscious, "players wait five seconds before respawning")
	controller._update_respawns(players, 1.0)
	_expect(not red._unconscious and not blue._unconscious, "both teams respawn automatically")
	_expect(red.position.z < 0.0 and blue.position.z > 0.0, "red and blue return to their own sides")
	for player in [red, blue]:
		var id := str(player.name).to_int()
		_expect(player.position.is_equal_approx(Net.spawn_position(id)), "respawn uses the assigned team slot")
		_expect(is_equal_approx(player.rotation.y, Net.spawn_rotation_y(id)), "respawn faces the opposing side")
		_expect(player.stamina == player.max_stamina and player.momentum == 0.0, "respawn resets stamina and momentum")
	cube.position = Vector3(8, 10, 0)
	cube.rotation.y = 0.7
	red.position = Vector3(8, 11.82, 0)
	await _tick(controller, 1.0)
	_expect(Net.cube_control == Net.CubeControl.RED and Net._round_red_score == 4, "capture follows moving rotated cube")
	Net._reset_round_scoreboard()
	_expect(Net._round_red_score == 0 and Net._round_blue_score == 0, "new round clears points")
	Net.net_sync_game_mode(Net.GameMode.NORMAL)
	Net._reset_round_scoreboard()
	_expect(cube.get_node("MeshInstance3D").material_override == original, "normal mode restores original cube")
	_expect(Net._round_red_goal == 1 and Net._round_blue_goal == 2, "normal goals stay opponent counts")
	teammate._unconscious = true
	Net.on_player_down()
	_expect(Net._round_blue_score == 1 and not Net._round_over, "normal faint scoring still works")
	await _tick(controller, 6.0)
	_expect(teammate._unconscious, "normal mode does not automatically respawn players")
	Net.net_sync_game_mode(Net.GameMode.KING_OF_CUBE)
	Net._reset_round_scoreboard()
	Net._round_red_score = 99
	Net.award_cube_point(0)
	_expect(Net._round_over and Net._round_red_score == 100, "100 points ends round")
	await get_tree().create_timer(3.0).timeout
	print("FAIL king of cube" if failed else "PASS king of cube")
	get_tree().quit(1 if failed else 0)


func _tick(controller: Node, seconds: float) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	controller._physics_process(seconds)


func _capture_cube(cube: Node3D, color: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var camera := Camera3D.new()
	get_tree().current_scene.add_child(camera)
	camera.global_position = cube.global_position + Vector3(4, 3, 5)
	camera.look_at(cube.global_position + Vector3.UP * 0.5)
	camera.current = true
	await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("/tmp/flowstate-cube-%s.png" % color)
	camera.queue_free()


func _choose_mode(mode: int) -> void:
	while not Transition.has_node("ServerPrompt"):
		await get_tree().process_frame
	var prompt := Transition.get_node("ServerPrompt")
	_expect(prompt._mode.get_item_text(0) == "Normal", "normal is default")
	_expect(prompt._mode.get_item_text(1) == "King of the Cube", "cube mode is available")
	for viewport_size in [Vector2i(1152, 648), Vector2i(640, 480)]:
		get_window().size = viewport_size
		await get_tree().create_timer(0.3).timeout
		var scroll: ScrollContainer = prompt.get_node("Margin/Scroll")
		_expect(prompt._panel.size.x <= scroll.size.x, "mode choice fits viewport")
		if DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png("/tmp/flowstate-mode-%d.png" % viewport_size.x)
	if mode < 0:
		var event := InputEventAction.new()
		event.action = "ui_cancel"
		event.pressed = true
		prompt._unhandled_input(event)
	else:
		prompt._mode.select(mode)
		prompt._submit()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
