extends Node

var failed := false
var trackers: Array[XRControllerTracker] = []
var combat: Node
var player: Node3D
var enemy: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(30).timeout.connect(func():
		push_error("FAIL vr arcade timeout")
		get_tree().quit(1))
	combat = Net.arcade
	combat.set_physics_process(false)
	Net.net_sync_game_mode(Net.GameMode.ARCADE)
	Net.round_state = Net.RoundState.PLAYING
	Net._round_over = false
	Net._add_player(2)
	player = combat._body(1)
	enemy = combat._body(2)
	player.team = 0
	enemy.team = 1
	enemy.set_multiplayer_authority(1)
	enemy.set_process_input(false)
	for body in [player, enemy]:
		body.freeze = true
		body.movement_locked = false
		body.set_physics_process(false)
		body.set_process(false)
	player.using_controller = true
	player._camera.reparent(self)
	get_parent().get_node("water base").set_physics_process(false)
	_expect(VR.start(true), "vr starts")
	for i in range(2):
		var tracker := XRControllerTracker.new()
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.name = "left_hand" if i == 0 else "right_hand"
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if i == 0 else XRPositionalTracker.TRACKER_HAND_RIGHT
		tracker.set_pose("grip", Transform3D(Basis.IDENTITY, Vector3(-0.3 if i == 0 else 0.3, 1.15, -0.5)),
			Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
		VR._hands.append(VR._origin.get_node("LeftHand" if i == 0 else "RightHand"))
	await _frames()
	for immersive in [false, true]:
		if immersive:
			VR.enter_immersive()
			await get_tree().create_timer(0.9).timeout
			VR.immersion.set_process(false)
		await _test_moves("immersive" if immersive else "couch")
	VR.stop()
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	print("FAIL vr arcade" if failed else "PASS vr arcade")
	get_tree().quit(1 if failed else 0)


func _test_moves(mode: String) -> void:
	_reset()
	player.position = Vector3(0, 20, 0)
	enemy.position = Vector3(0, 20, -10)
	var camera := VR.view_camera(player._camera)
	camera.global_position = player.position + Vector3(0, 2, 3)
	camera.look_at(enemy.position)
	camera.rotate_y(deg_to_rad(20.0))
	await _frames()
	_expect(combat.pick_target(player) == 2, mode + " dash accepts a nearby off center enemy")
	var saved := enemy.position
	enemy.position.z = 10
	_expect(combat.pick_target(player) == 0, mode + " dash ignores enemies behind the camera")
	enemy.position.z = -50
	_expect(combat.pick_target(player) == 0, mode + " dash respects range")
	enemy.position = saved
	enemy.team = player.team
	_expect(combat.pick_target(player) == 0, mode + " dash ignores teammates")
	enemy.team = 1
	combat._hud._process(0.0)
	_expect(combat._hud.prompt.text.contains("Left Trigger"), mode + " hud names the dash button")
	_expect(combat._hud.marker.position.is_equal_approx(
		VR.project_ui_position(enemy.position, player._camera) - combat._hud.marker.size * 0.5), mode + " target marker uses the active view")
	_expect(combat._hud.marker.visible and not combat._hud.lock_status.visible, mode + " locked target hides the warning")
	_expect(combat._hud.marker.get_theme_font_size("font_size") == 48, mode + " crosshair is larger")
	_expect(combat._hud.marker.get_theme_color("font_color").r == 1.0, mode + " crosshair is red")
	_capture(mode + "-locked")
	enemy.team = player.team
	combat._hud._process(0.0)
	_expect(combat._hud.marker.visible and combat._hud.lock_status.visible, mode + " missing target shows crosshair and warning")
	_expect(combat._hud.lock_status.text == "Not locked on", mode + " missing target names its state")
	_expect(combat._hud.marker.position.is_equal_approx(player.Controller.aim_position(player) - combat._hud.marker.size * 0.5), mode + " unlocked crosshair follows aim")
	_expect(not combat._hud.marker.get_rect().intersects(combat._hud.lock_status.get_rect()), mode + " lock status does not overlap crosshair")
	_capture(mode + "-unlocked")
	player._unconscious = true
	combat._hud._process(0.0)
	_expect(not combat._hud.marker.visible and not combat._hud.lock_status.visible, mode + " fainted player has no targeting ui")
	player._unconscious = false
	enemy.team = 1
	trackers[0].set_input("trigger", 1.0)
	await _frames()
	_expect(combat.states.get(1, {}).get("phase", -1) == combat.Phase.DASH, mode + " trigger starts dash")
	trackers[0].set_input("trigger", 0.0)
	await _frames()
	if combat.states.has(1):
		combat.submit(2, combat.Action.Q, 1)
		combat._start_clash(1, 2)
		for hand in [0, 1]:
			trackers[hand].set_input("trigger", 1.0)
			await _frames()
			trackers[hand].set_input("trigger", 0.0)
			await _frames()
		_expect(combat.states[1].score == 2, mode + " alternating triggers advances clash")
	_reset()
	player.position = Vector3(0, 24, 0)
	enemy.position = Vector3(0, 20, 0)
	camera.global_position = player.position + Vector3(0, 2, 3)
	camera.global_rotation = Vector3.ZERO
	_expect(combat.pick_pound_target(player) == 2, mode + " ground pound finds an enemy below without looking down")
	enemy.team = player.team
	_expect(combat.pick_pound_target(player) == 0, mode + " ground pound ignores teammates")
	enemy.team = 1
	enemy.position.y = 25
	_expect(combat.pick_pound_target(player) == 0, mode + " ground pound ignores enemies above")
	enemy.position = Vector3(13, 20, 0)
	_expect(combat.pick_pound_target(player) == 0, mode + " ground pound respects horizontal range")
	enemy.position = Vector3(0, 20, 0)
	for jump_first in [false, true]:
		await _pound(mode, jump_first)
		player.position = Vector3(0, 24, 0)


func _pound(mode: String, jump_first: bool) -> void:
	enemy.stamina = 200
	await _frames()
	trackers[1 if jump_first else 0].set_input("ax_button" if jump_first else "primary_click", true)
	await _frames()
	trackers[0 if jump_first else 1].set_input("primary_click" if jump_first else "ax_button", true)
	await _frames()
	_expect(combat.states.get(1, {}).get("phase", -1) == combat.Phase.POUND, mode + " stick and a starts ground pound")
	for i in range(20):
		combat._physics_process(0.016)
	_expect(enemy.stamina == 125, mode + " ground pound deals damage")
	trackers[0].set_input("primary_click", false)
	trackers[1].set_input("ax_button", false)
	await _frames()
	_reset()


func _reset() -> void:
	for id in combat.states.keys():
		combat._release(id)
	combat._publish(true)
	combat._cooldowns.clear()
	combat._last_targets.clear()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Input.flush_buffered_events()


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("/tmp/flowstate-arcade-" + label + ".png")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
