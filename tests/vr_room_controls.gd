extends Node

var failed := false
var trackers: Array[XRControllerTracker] = []
var clicks := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(30).timeout.connect(func():
		push_error("FAIL room controls timeout")
		get_tree().quit(1))
	await get_tree().create_timer(0.8).timeout
	_expect(VR.start(true), "room starts")
	var room = VR._room_root
	for i in range(2):
		var tracker := XRControllerTracker.new()
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.name = "left_hand" if i == 0 else "right_hand"
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
		VR._hands.append(VR._origin.get_node("LeftHand" if i == 0 else "RightHand"))
	_aim(0, Vector3(-4, 1, -2))
	_aim(1, Vector3(4, 1, -2))
	await get_tree().create_timer(0.9).timeout
	_button("Settings").pressed.connect(func(): clicks += 1)
	_aim_ui(1, _button("Settings").get_global_rect().get_center())
	await get_tree().create_timer(0.15).timeout
	_expect(_button("Settings").is_hovered(), "right pointer hovers the tv button")
	_expect(VR._hands[1].get_node("Pointer/Tip").visible, "pointer has a visible hit marker")
	await _trigger(1, true)
	await _trigger(1, false)
	await get_tree().create_timer(0.9).timeout
	_expect(clicks == 1 and _button("Back") != null, "trigger clicks the settings button once")
	var scroll: ScrollContainer = get_parent().get_node("UI/MenuScroll")
	_aim_ui(1, get_tree().root.get_visible_rect().size * Vector2(0.5, 0.7))
	trackers[1].set_input("primary", Vector2(0, -1))
	await get_tree().create_timer(0.7).timeout
	trackers[1].set_input("primary", Vector2.ZERO)
	_expect(scroll.scroll_vertical > 0, "pointing at the tv scrolls settings")
	scroll.ensure_control_visible(_button("Back"))
	await get_tree().create_timer(0.15).timeout
	_aim_ui(0, _button("Back").get_global_rect().get_center())
	await get_tree().create_timer(0.15).timeout
	await _trigger(0, true)
	await _trigger(0, false)
	await get_tree().create_timer(0.9).timeout
	_expect(_button("Play") != null, "left pointer can click a different tv button")
	_button("Settings").pressed.connect(func(): clicks += 1)

	var light_switch: Node3D = room.get_node("Room/LightSwitch")
	var menu: Control = get_parent().get_node("UI/MenuScroll/MenuScreen")
	menu.remove_from_group("controller_menu")
	VR._pelt_hand = -1
	_aim(1, light_switch.global_position)
	await get_tree().create_timer(0.15).timeout
	await _trigger(1, true)
	_expect(not room.lights_on and not VR._light.visible, "switch turns off the room light")
	_expect(VR._room_environment.ambient_light_energy == 0.0, "switch removes ambient light")
	_expect(room.get_node("Room/GameScreen/TVGlow").visible, "tv supplies the remaining light")
	await get_tree().create_timer(0.3).timeout
	_expect(not room.lights_on, "holding the trigger does not repeatedly toggle")
	_expect(VR._pelt_hand == -1 and not Input.is_action_pressed("water_pelt"), "switch click does not fire an attack even outside menus")
	_capture("dark")
	await _trigger(1, false)
	await _trigger(1, true)
	await _trigger(1, false)
	_expect(room.lights_on and VR._light.visible, "switch turns lights back on")
	_expect(is_equal_approx(VR._room_environment.ambient_light_energy, 0.8), "switch restores ambient light")
	_capture("lit")
	menu.add_to_group("controller_menu")

	# losing tracking releases a held click without activating it
	_aim_ui(1, _button("Settings").get_global_rect().get_center())
	await get_tree().create_timer(0.15).timeout
	await _trigger(1, true)
	trackers[1].invalidate_pose("grip")
	trackers[1].invalidate_pose("aim")
	await get_tree().create_timer(0.15).timeout
	_expect(clicks == 1 and room._pressed_hand == -1, "tracking loss cancels the click")
	_expect(not VR._hands[1].get_node("Pointer").visible, "lost controller hides its pointer")
	_aim_ui(1, _button("Settings").get_global_rect().get_center())
	await get_tree().create_timer(0.15).timeout
	_expect(room._pressed_hand == -1, "regaining tracking while held does not start another click")
	await _trigger(1, false)
	_aim(1, light_switch.global_position)
	await get_tree().create_timer(0.15).timeout
	await _trigger(1, true)
	await _trigger(1, false)
	_expect(not room.lights_on, "switch remains usable after tracking returns")

	await VR.enter_immersive()
	_expect(not VR._hands[0].get_node("Pointer").visible and not VR._hands[1].get_node("Pointer").visible, "room pointers stay out of immersive gameplay")
	await VR.exit_immersive()
	_expect(not room.lights_on and not VR._light.visible, "dark room survives immersive round trip")
	_expect(room.get_node("Room/GameScreen/TVGlow").visible, "tv glow returns with the room")
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	VR.stop()
	print("FAIL vr room controls" if failed else "PASS vr room controls")
	get_tree().quit(1 if failed else 0)


func _aim(hand: int, target: Vector3) -> void:
	var from := Vector3(-0.25 if hand == 0 else 0.25, 1.2, 1.2)
	var inverse: Transform3D = VR._origin.global_transform.affine_inverse()
	var aim := inverse * Transform3D(Basis.looking_at(target - from), from)
	var grip := Transform3D(Basis(Vector3.RIGHT, 0.8), aim.origin)
	trackers[hand].set_pose("grip", grip, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	trackers[hand].set_pose("aim", aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _aim_ui(hand: int, pixel: Vector2) -> void:
	var screen: MeshInstance3D = VR._room.get_node("GameScreen")
	var uv := pixel / get_tree().root.get_visible_rect().size
	_aim(hand, screen.to_global(Vector3((uv.x - 0.5) * screen.mesh.size.x, (0.5 - uv.y) * screen.mesh.size.y, 0.003)))


func _trigger(hand: int, pressed: bool) -> void:
	trackers[hand].set_input("trigger", 1.0 if pressed else 0.0)
	await get_tree().create_timer(0.12).timeout


func _button(label: String) -> BaseButton:
	for button in get_parent().get_node("UI/MenuScroll/MenuScreen")._buttons:
		if button is BaseButton and button.button_text == label:
			return button
	return null


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	VR.room_view.get_texture().get_image().save_png("/tmp/flowstate-room-%s.png" % label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
