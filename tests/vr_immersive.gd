extends Node

const Gestures := preload("res://vr/gestures.gd")
const Arms := preload("res://water/player/vr_arms.gd")
var failed := false
var trackers: Array[XRControllerTracker] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(60).timeout.connect(func():
		push_error("FAIL immersive timeout")
		get_tree().quit(1))
	_test_gestures()
	_expect(VR.start(true), "preview starts")
	_expect(not VR._origin.is_physics_interpolated(), "tracked rig does not interpolate stale physics poses")
	await get_tree().create_timer(0.8).timeout
	VR.enter_immersive()
	_expect(VR.entering and not VR.immersive, "tv zoom precedes immersive view")
	await get_tree().create_timer(0.9).timeout
	_expect(VR.immersive and not VR.entering, "zoom finishes")
	_expect(VR.room_view.world_3d == get_tree().root.world_3d, "immersive shares menu world")
	_expect(get_tree().root.disable_3d and get_tree().root.transparent_bg, "root renders transparent ui only")
	_expect(VR.immersion.blur.visible, "menu background blurred")
	await get_tree().create_timer(0.6).timeout
	_capture("menu")
	Net.start_solo_play()
	while not Net._round_started or Net.arcade._body(1) == null:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var player = Net.arcade._body(1)
	while player.movement_locked or Transition._fade_rect.color.a > 0.001 or float(Transition._blur_mat.get_shader_parameter("amount")) > 0.001:
		await get_tree().process_frame
	player.freeze = true
	player.position = Vector3(-5, 7.5, 0)
	player.reset_physics_interpolation()
	VR._head.rotation = Vector3.ZERO
	for i in range(2):
		var tracker := XRControllerTracker.new()
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.name = "left_hand" if i == 0 else "right_hand"
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if i == 0 else XRPositionalTracker.TRACKER_HAND_RIGHT
		tracker.set_pose("grip", Transform3D(Basis.IDENTITY, Vector3(-0.3 if i == 0 else 0.3, 1.15, -0.5)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
		var hand := XRController3D.new()
		hand.tracker = tracker.name
		hand.pose = &"grip"
		VR._origin.add_child(hand)
		VR._hands.append(hand)
	await get_tree().create_timer(0.3).timeout
	_expect(not VR.immersion.blur.visible, "gameplay is sharp")
	_expect(not Transition._fade_rect.visible and not Transition._blur_rect.visible, "fullscreen overlays stay off the ui panel")
	_expect(VR._head.global_position.distance_to(player.global_position + Vector3.UP * Arms.EYE_HEIGHT) < 0.05, "camera at raised face height")
	_expect(not player.get_node("blockbench_export").visible, "own body hidden")
	_expect(player.vr_arms.visible and player.vr_arms._hands[0].visible, "tracked arms visible")
	_expect(player.replicated_vr_pose.size() == 4 and player.replicated_vr_pose[3] == 3, "both tracked hands published")
	var wrist: Transform3D = player.replicated_vr_pose[1]
	_expect((player.global_transform * wrist).is_equal_approx(VR._hands[0].global_transform), "hands match controller grip without an offset")
	for i in range(2):
		_expect(player.vr_arms._hands[i].global_transform.is_equal_approx(VR._hands[i].global_transform), "visible hand matches controller grip")
	_expect((player.global_transform * wrist).origin.is_equal_approx(VR.immersion.hand_transform(VR._hands[0]).origin), "rendered and gesture hands agree")
	var head_position: Vector3 = VR._head.position
	VR._head.position.x += 4.0
	for i in range(10):
		await get_tree().process_frame
		_expect(not player.get_node("blockbench_export").visible, "invalid tracking never reveals own body")
		_expect(player.vr_arms.visible and player.vr_arms._hands[0].visible, "network pose limits never hide local hands")
	_expect(player.replicated_vr_pose.is_empty(), "invalid pose reproduces old visibility fallback")
	VR._head.position = head_position
	await get_tree().process_frame
	await get_tree().process_frame
	var lifeguard: bool = player.is_lifeguard
	player.is_lifeguard = not lifeguard
	_expect(not player.get_node("blockbench_export").visible, "replacement body is hidden immediately")
	await get_tree().process_frame
	await get_tree().process_frame
	player.is_lifeguard = lifeguard
	await get_tree().process_frame
	await get_tree().process_frame
	var pose: Array = player.replicated_vr_pose.duplicate()
	_expect(Arms.valid_pose(pose), "pose validates")
	pose[1].origin.x = 100.0
	_expect(not Arms.valid_pose(pose), "unreachable pose rejected")
	_capture("game")
	var probe := MeshInstance3D.new()
	probe.mesh = BoxMesh.new()
	probe.layers = 5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.MAGENTA
	probe.material_override = material
	player.add_child(probe)
	probe.position = Vector3(0, Arms.EYE_HEIGHT, -0.35)
	player.get_node("blockbench_export").show()
	player.vr_arms._sync_body_visibility()
	_expect(probe.layers == 0, "new body geometry is excluded from all cameras")
	for mesh in player._mesh_instances_in(player.get_node("blockbench_export")):
		mesh.show()
		_expect(mesh.layers == 0, "visible flags cannot reveal body meshes")
	_expect(player.vr_arms._hands[0].layers != 0, "controller hands remain renderable")
	_capture("body-hidden")
	VR._head.rotation.x = -0.6
	await get_tree().process_frame
	await get_tree().process_frame
	_capture("hands")
	VR._head.rotation.x = 0.0
	var immersion = VR.immersion
	_expect(immersion.hand_mode == Gestures.HandMode.ATTACK and not immersion.swim_enabled, "upright controllers select attacks")
	player.set_physics_process(false)
	var stamina: float = player.stamina
	for i in range(27):
		var at := Vector3(-0.3, 1.15, -0.5 - minf(i / 20.0, 1.0) * 0.45)
		trackers[0].set_pose("grip", Transform3D(Basis.IDENTITY, at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await get_tree().process_frame
		immersion.combat(player, 0.02)
	_expect(player.stamina < stamina and player._water_power_cooldown_timer > 0.0, "tracked hand motion launches attack")
	player._water_power_cooldown_timer = 0.0
	stamina = player.stamina
	immersion.apply_gesture(player, {"kind": "wave", "direction": Vector3.FORWARD, "distance": 0.5}, player.global_position)
	_expect(player.stamina < stamina, "gesture attack spends stamina")
	player._water_power_cooldown_timer = 0.0
	immersion.apply_gesture(player, {"kind": "wall"}, player.global_position)
	stamina = player.stamina
	immersion.apply_gesture(player, {"kind": "wave", "direction": Vector3.FORWARD, "distance": 0.5}, player.global_position)
	_expect(player.stamina == stamina, "wall gesture blocks attack")
	immersion.combat(player, 0.02)
	_expect(player._water_wall_up and player.stamina < stamina, "wall appears and drains stamina")
	await _orient_hands(true)
	_expect(immersion.hand_mode == Gestures.HandMode.SWIM and immersion.swim_enabled, "inward rings select swimming")
	_expect(not player._water_wall_up, "turning controllers inward stops the wall")
	stamina = player.stamina
	immersion.apply_gesture(player, {"kind": "wave", "direction": Vector3.FORWARD, "distance": 0.5}, player.global_position)
	immersion.apply_gesture(player, {"kind": "wall"}, player.global_position)
	_expect(player.stamina == stamina and not player._water_wall_up, "swimming cannot cast attacks")
	Input.action_press("pad_move_up")
	player.momentum = 0.0
	for i in range(200):
		immersion.swim(player, 0.02)
	var normal: float = player.momentum
	immersion.apply_gesture(player, {"kind": "stroke"}, player.global_position)
	for i in range(200):
		immersion.swim(player, 0.02)
	_expect(player.momentum > normal, "arm strokes boost swimming")
	Input.action_release("pad_move_up")
	Input.action_press("pad_move_down")
	immersion.swim(player, 0.02)
	_expect(player.dir.dot(VR._head.global_basis.z) > 0.0, "backstroke moves backwards")
	Input.action_release("pad_move_down")
	await _orient_hands(false)
	_expect(not immersion.swim_enabled and immersion.stroke_boost == 0.0, "upright rings stop swimming boost")
	immersion.apply_gesture(player, {"kind": "stroke"}, player.global_position)
	_expect(immersion.stroke_boost == 0.0, "attack posture cannot produce swim strokes")
	await _test_continuous(player)
	await _test_tracked_attacks(player)
	trackers[0].set_input("primary", Vector2(0.5, 0.8))
	trackers[1].set_input("primary", Vector2(0.5, 0.8))
	trackers[0].set_input("ax_button", true)
	trackers[1].set_input("by_button", true)
	trackers[0].set_input("trigger", 1.0)
	await get_tree().process_frame
	Input.flush_buffered_events()
	_expect(is_zero_approx(float(VR._axes.get(3, 0.0))), "right stick pitch disabled")
	_expect(not Input.is_action_pressed("water_power") and not Input.is_action_pressed("water_counter") and not Input.is_action_pressed("water_attack"), "vr attack buttons disabled")
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(player.vr_arms._hands[0].visible, "brief tracking loss keeps the last hand pose")
	await get_tree().create_timer(0.5).timeout
	_expect(player.replicated_vr_pose[3] == 0, "lost tracking clears hand mask")
	_expect(immersion.hand_mode == Gestures.HandMode.NEUTRAL and not immersion.swim_enabled, "tracking loss cancels controller mode")
	_expect(not player.get_node("blockbench_export").visible, "tracking loss keeps own body hidden")
	Net.enter_spectator_after_faint()
	await get_tree().create_timer(0.1).timeout
	_expect(player.replicated_vr_pose.is_empty(), "spectators stop publishing their arms")
	_expect(VR._head.global_position.distance_to(Net._spectator_camera.global_position) < 2.0, "spectator view follows spectator camera")
	Net.exit_spectator_mode()
	VR.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not get_tree().root.disable_3d and not get_tree().root.transparent_bg, "desktop render restored")
	_expect(Transition._fade_rect.visible and Transition._blur_rect.visible, "desktop overlays restored")
	_expect(player.get_node("blockbench_export").visible and not player.vr_arms.visible, "body restored on vr exit")
	_expect(probe.layers == 5, "body render layers restored on vr exit")
	VR.start(true)
	await VR.enter_immersive()
	Net._leave_current_game_to_menu(true)
	await get_tree().create_timer(0.8).timeout
	_expect(VR.immersive and VR.immersion.player == null and VR.immersion.blur.visible, "leaving game restores immersive menu")
	VR.stop()
	print("FAIL immersive vr" if failed else "PASS immersive vr")
	get_tree().quit(1 if failed else 0)


func _test_gestures() -> void:
	var left := Transform3D(Basis.IDENTITY, Vector3(-0.3, 0, 0))
	var right := Transform3D(Basis.IDENTITY, Vector3(0.3, 0, 0))
	_expect(Gestures.hand_mode(left, right) == Gestures.HandMode.ATTACK, "rings up selects attacks")
	left.basis = Basis(Vector3.BACK, -PI / 2.0)
	right.basis = Basis(Vector3.BACK, PI / 2.0)
	_expect(Gestures.hand_mode(left, right) == Gestures.HandMode.SWIM, "rings facing each other selects swim")
	var turn := Transform3D(Basis(Vector3.UP, 1.2), Vector3.ZERO)
	_expect(Gestures.hand_mode(turn * left, turn * right, Gestures.HandMode.NEUTRAL, turn.basis) == Gestures.HandMode.SWIM, "turning does not change controller mode")
	left.origin.z = -0.8
	right.origin.z = 0.4
	_expect(Gestures.hand_mode(left, right) == Gestures.HandMode.SWIM, "alternating strokes do not change controller mode")
	right.basis = Basis.IDENTITY
	_expect(Gestures.hand_mode(left, right) == Gestures.HandMode.NEUTRAL, "mixed controller posture is neutral")
	left.basis = Basis(Vector3.BACK, PI / 2.0)
	right.basis = Basis(Vector3.BACK, -PI / 2.0)
	_expect(Gestures.hand_mode(left, right) == Gestures.HandMode.NEUTRAL, "outward rings do not swim")
	left.basis = Basis(Vector3.BACK, -deg_to_rad(35))
	right.basis = Basis(Vector3.BACK, deg_to_rad(35))
	_expect(Gestures.hand_mode(left, right, Gestures.HandMode.SWIM) == Gestures.HandMode.SWIM, "small wrist rotations do not flicker modes")
	var short := _sweep(Vector3.FORWARD * 0.3, 0.0)
	var long := _sweep(Vector3.FORWARD * 0.8, 0.0)
	_expect(short.get("kind") == "wave" and long.get("kind") == "wave", "forward sweeps launch waves")
	_expect(Gestures.wave_strength(long.get("distance", 0.0)) > Gestures.wave_strength(short.get("distance", 0.0)), "longer sweep travels farther")
	_expect(_sweep(Vector3.RIGHT * 0.4, 0.0).get("kind") == "wall", "side sweep raises wall")
	_expect(_sweep(Vector3.BACK * 0.4, -1.0).get("kind") == "stroke", "forward swimming pull")
	_expect(_sweep(Vector3.BACK * 0.4, 0.0, true, Gestures.HandMode.SWIM).get("kind") == "stroke", "arm strokes work without holding the stick")
	_expect(_sweep(Vector3.FORWARD * 0.4, 1.0).get("kind") == "stroke", "backstroke swimming push")
	_expect(_sweep(Vector3.FORWARD * 0.03, 0.0).is_empty(), "jitter ignored")
	_expect(_sweep(Vector3.FORWARD * 0.4, 0.0, false).is_empty(), "dry movement ignored")
	var gestures := Gestures.new()
	gestures.sample(0, Vector3.ZERO, true, true, 0.0, 0.02)
	_expect(gestures.sample(0, Vector3.FORWARD * 5.0, true, true, 0.0, 0.02).is_empty(), "tracking jump ignored")
	_expect(gestures.sample(0, Vector3.FORWARD, true, false, 0.0, 0.02).is_empty(), "tracking loss ignored")


func _sweep(displacement: Vector3, movement: float, wet := true, mode := -1) -> Dictionary:
	var gestures := Gestures.new()
	var result := {}
	if mode == -1:
		mode = Gestures.HandMode.SWIM if movement != 0.0 else Gestures.HandMode.ATTACK
	for i in range(21):
		var event := gestures.sample(0, displacement * i / 20.0, wet, true, movement, 0.02, Basis.IDENTITY, mode)
		if not event.is_empty():
			result = event
	for i in range(6):
		var event := gestures.sample(0, displacement, wet, true, movement, 0.02, Basis.IDENTITY, mode)
		if not event.is_empty():
			result = event
	return result


func _orient_hands(swimming: bool) -> void:
	for i in range(2):
		var rotation := Basis(Vector3.BACK, (-PI / 2.0 if i == 0 else PI / 2.0)) if swimming else Basis.IDENTITY
		trackers[i].set_pose("grip", Transform3D(rotation, VR._hands[i].position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await get_tree().process_frame
	await get_tree().create_timer(0.18).timeout


func _test_continuous(player) -> void:
	var immersion = VR.immersion
	await _orient_hands(true)
	player.momentum = 0.0
	player.stamina = 100.0
	player.set_physics_process(true)
	player.freeze = false
	trackers[0].set_input("primary", Vector2(0, 1))
	var start: Vector3 = player.position
	var min_speed := INF
	var boost_seen := false
	var elapsed := 0.0
	while elapsed < 3.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		for i in range(2):
			var side := -1.0 if i == 0 else 1.0
			var roll := side * (PI / 2.0 + 0.3 * sin(elapsed * 4.0))
			var at := Vector3(side * 0.3, 1.15, -0.5 + 0.4 * sin(elapsed * 5.0 + i * PI))
			trackers[i].set_pose("grip", Transform3D(Basis(Vector3.BACK, roll), at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		_expect(immersion.swim_enabled, "alternating strokes keep swimming enabled")
		_expect(player.vr_arms.visible and player.vr_arms._hands[0].visible and player.vr_arms._hands[1].visible, "hands stay visible during sustained swimming")
		boost_seen = boost_seen or immersion.stroke_boost > 0.0
		if elapsed > 1.0:
			min_speed = minf(min_speed, Vector2(player.linear_velocity.x, player.linear_velocity.z).length())
	_expect(boost_seen, "real controller strokes produce swimming boost")
	_expect(min_speed > 0.2 and player.position.distance_to(start) > 1.0, "swimming moves continuously instead of in increments")
	XRServer.remove_tracker(trackers[0])
	await get_tree().create_timer(0.1).timeout
	_expect(player.vr_arms._hands[0].visible and player.vr_arms._hands[1].visible, "one occluded controller does not hide both hands")
	_expect(immersion.swim_enabled and player.momentum > 0.0, "brief controller occlusion does not stop swimming")
	XRServer.add_tracker(trackers[0])
	trackers[0].set_input("primary", Vector2.ZERO)
	player.freeze = true
	player.set_physics_process(false)
	player.linear_velocity = Vector3.ZERO
	player.position = start
	player.reset_physics_interpolation()
	await _orient_hands(false)
	await get_tree().process_frame
	_expect(player.vr_arms._hands[0].global_position.distance_to(VR._hands[0].global_position) < 0.01, "recovered controller resumes exact hand tracking")


func _test_tracked_attacks(player) -> void:
	var previous_fps := Engine.max_fps
	Engine.max_fps = 30
	player.set_physics_process(true)
	for sweep in range(3):
		var rotation := Basis(Vector3.RIGHT, deg_to_rad(50.0))
		var start := Vector3(-0.3, 1.15, -0.35)
		trackers[0].set_pose("grip", Transform3D(rotation, start), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await get_tree().create_timer(0.2).timeout
		player.stamina = 100.0
		player._water_power_cooldown_timer = 0.0
		VR.immersion.gestures.reset()
		var elapsed := 0.0
		while elapsed < 0.8:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			var direction := Vector3.RIGHT if sweep == 2 else Vector3.FORWARD
			var at := start + direction * 0.55 * minf(elapsed / 0.55, 1.0)
			trackers[0].set_pose("grip", Transform3D(rotation, at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
			_expect(player.vr_arms._hands[0].visible and player.vr_arms._hands[1].visible, "water moves keep both hands visible")
		if sweep == 2:
			_expect(player._water_wall_up, "tracked sideways sweep raises a wall")
		else:
			_expect(player._water_power_cooldown_timer > 0.0, "repeated tracked forward sweeps launch waves")
	await _orient_hands(true)
	_expect(not player._water_wall_up, "swimming cancels the tracked wall")
	player.set_physics_process(false)
	await _orient_hands(false)
	Engine.max_fps = previous_fps


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw()
	var picture := VR.room_view.get_texture().get_image()
	picture.save_png("/tmp/flowstate-immersive-" + label + ".png")
	var first := picture.get_pixel(0, 0)
	var different := 0
	for y in range(0, picture.get_height(), 24):
		for x in range(0, picture.get_width(), 24):
			var color := picture.get_pixel(x, y)
			if label == "body-hidden":
				_expect(not (color.r > 0.8 and color.b > 0.8 and color.g < 0.2), "hidden body probe does not render")
			if Vector3(color.r, color.g, color.b).distance_to(Vector3(first.r, first.g, first.b)) > 0.05:
				different += 1
	_expect(different > 100, label + " renders nonblank pixels")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
