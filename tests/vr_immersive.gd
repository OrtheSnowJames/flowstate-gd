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
	var hand_offset := Vector3(0, 0, -0.045)
	_expect((player.global_transform * wrist).is_equal_approx(VR._hands[0].global_transform.translated_local(hand_offset)), "fallback hands sit slightly ahead of controller grip")
	for i in range(2):
		_expect(player.vr_arms._hands[i].global_transform.is_equal_approx(VR._hands[i].global_transform.translated_local(hand_offset)), "visible hand uses grip offset")
	_expect(VR.immersion.hand_transform(VR._hands[0]).is_equal_approx(VR._hands[0].global_transform), "fallback gestures retain grip tracking")
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
	_check_model_arms(player)
	VR._head.rotation.x = -0.6
	await get_tree().process_frame
	await get_tree().process_frame
	_capture("lifeguard-arms" if player.is_lifeguard else "normal-arms")
	VR._head.rotation.x = 0.0
	player.is_lifeguard = lifeguard
	await get_tree().process_frame
	await get_tree().process_frame
	_check_model_arms(player)
	VR._head.rotation.x = -0.6
	await get_tree().process_frame
	await get_tree().process_frame
	_capture("lifeguard-arms" if player.is_lifeguard else "normal-arms")
	VR._head.rotation.x = 0.0
	var team: int = player.team
	player.team = 1 if team == 0 else 0
	await get_tree().process_frame
	await get_tree().process_frame
	_check_model_arms(player)
	player.team = team
	await get_tree().process_frame
	await get_tree().process_frame
	var aim: Transform3D = trackers[0].get_pose("grip").transform
	aim.origin += Vector3(0, 0.03, -0.12)
	aim.basis = Basis(Vector3.RIGHT, -0.2)
	trackers[0].set_pose("aim", aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_model_arms(player)
	var tip_pose: Transform3D = VR._origin.global_transform * trackers[0].get_pose("aim").get_adjusted_transform()
	tip_pose = tip_pose.translated_local(hand_offset)
	_expect(player.vr_arms._hands[0].global_transform.is_equal_approx(tip_pose), "arm follows controller aim pose")
	_expect((player.global_transform * player.replicated_vr_pose[1]).is_equal_approx(tip_pose), "controller tip pose is replicated")
	_expect(VR.immersion.hand_transform(VR._hands[0]).is_equal_approx(VR._hands[0].global_transform), "gestures retain grip tracking")
	trackers[0].invalidate_pose("aim")
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
	for mesh in player._mesh_instances_in(player.vr_arms):
		_expect(mesh.layers != 0, "controller arms remain renderable")
	_capture("body-hidden")
	VR._head.rotation.x = -0.6
	await get_tree().process_frame
	await get_tree().process_frame
	_capture("hands")
	VR._head.rotation.x = 0.0
	var immersion = VR.immersion
	await _test_gesture_controls(player)
	await _test_swimming(player)
	await _test_pelts(player)
	await _test_cube_hands(player)
	trackers[0].set_input("primary", Vector2(0.5, 0.8))
	trackers[1].set_input("primary", Vector2(0.5, 0.8))
	trackers[0].set_input("ax_button", true)
	trackers[1].set_input("by_button", true)
	trackers[0].set_input("trigger", 1.0)
	await get_tree().process_frame
	Input.flush_buffered_events()
	_expect(is_zero_approx(float(VR._axes.get(3, 0.0))), "right stick pitch disabled")
	_expect(not Input.is_action_pressed("water_power") and not Input.is_action_pressed("water_counter") and not Input.is_action_pressed("water_attack"), "other vr attack buttons stay disabled")
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(player.vr_arms._hands[0].visible, "brief tracking loss keeps the last hand pose")
	await get_tree().create_timer(0.5).timeout
	_expect(player.replicated_vr_pose[3] == 0, "lost tracking clears hand mask")
	_expect(not immersion.swim_enabled, "tracking loss cancels swimming")
	_expect(not player.get_node("blockbench_export").visible, "tracking loss keeps own body hidden")
	Net.enter_spectator_after_faint()
	await get_tree().create_timer(0.1).timeout
	_expect(player.replicated_vr_pose.is_empty(), "spectators stop publishing their arms")
	_expect(VR._head.global_position.distance_to(Net._spectator_camera.global_position) < 2.0, "spectator view follows spectator camera")
	Net.exit_spectator_mode()
	await VR.exit_immersive()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(VR.active and not VR.immersive and VR._room.is_inside_tree(), "leaving immersive keeps xr active in the room")
	_expect(not get_tree().root.disable_3d and not get_tree().root.transparent_bg, "desktop render restored")
	_expect(Transition._fade_rect.visible and Transition._blur_rect.visible, "desktop overlays restored")
	_expect(player.get_node("blockbench_export").visible and not player.vr_arms.visible, "body restored on vr exit")
	_expect(probe.layers == 5, "body render layers restored on vr exit")
	VR.stop()
	VR.start(true)
	await VR.enter_immersive()
	Net._leave_current_game_to_menu(true)
	await get_tree().create_timer(0.8).timeout
	_expect(VR.immersive and VR.immersion.player == null and VR.immersion.blur.visible, "leaving game restores immersive menu")
	VR.stop()
	print("FAIL immersive vr" if failed else "PASS immersive vr")
	get_tree().quit(1 if failed else 0)


func _check_model_arms(player) -> void:
	for i in range(2):
		var source: Node3D = player.vr_arms._original_arms[i]
		var arm: Node3D = player.vr_arms._hands[i].get_node("Arm")
		var originals: Array = player._mesh_instances_in(source)
		var copies: Array = player._mesh_instances_in(arm)
		_expect(not copies.is_empty() and copies.size() == originals.size(), "vr uses every mesh from the current player arm")
		var bounds := AABB()
		var first := true
		for mesh in copies:
			var box: AABB = (arm.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		var tip := bounds.get_center()
		tip.y = bounds.end.y
		_expect((arm.global_transform * tip).distance_to(VR.immersion.hand_tip_transform(VR._hands[i]).origin) < 0.001, "arm tip matches controller tip")
		_expect(arm.basis.y.normalized().dot(Vector3.FORWARD) > 0.999, "model arm orientation is reversed from the old backwards mount")
		for mesh in originals:
			var copy: MeshInstance3D = arm.get_node(source.get_path_to(mesh))
			_expect(copy.mesh == mesh.mesh, "vr uses the actual normal or lifeguard arm geometry")
			_expect(copy.layers != 0 and copy.is_visible_in_tree(), "copied arm is visible while the body stays hidden")
			for surface in range(mesh.mesh.get_surface_count()):
				_expect(copy.get_active_material(surface) == mesh.get_active_material(surface), "vr arm keeps the model texture and team colors")
		_expect(arm.scale.is_equal_approx(player.get_node("blockbench_export").scale), "vr arm keeps the player model scale")
	_expect(not player.get_node("blockbench_export").visible, "model arm swap never reveals the body")


func _test_gestures() -> void:
	var short := _sweep(Vector3.FORWARD * 0.3)
	var long := _sweep(Vector3.FORWARD * 0.8)
	_expect(short.get("kind") == "wave" and long.get("kind") == "wave", "forward water sweeps still launch waves")
	_expect(Gestures.wave_strength(long.get("distance", 0.0)) > Gestures.wave_strength(short.get("distance", 0.0)), "longer sweep travels farther")
	for direction in [Vector3.LEFT, Vector3.RIGHT]:
		_expect(_sweep(direction * 0.4).get("kind") == "stroke", "sideways water sweeps swim")
		_expect(_sweep(direction * 0.4, false).get("kind") == "wall", "the same sideways sweep in air raises a wall")
	_expect(_sweep(Vector3.FORWARD * 0.4, false).is_empty(), "forward air sweeps do not launch waves")
	_expect(_sweep(Vector3.UP * 0.4).is_empty(), "lifting controllers alone does not swim")
	_expect(_sweep(Vector3.RIGHT * 0.03).is_empty(), "small hand motion does not swim")
	_expect(_sweep(Vector3.RIGHT * 0.4, true, Basis(Vector3.UP, 1.2)).get("kind") == "stroke", "sideways strokes follow the headset heading")
	var gestures := Gestures.new()
	gestures.sample(0, Vector3.ZERO, true, true, 0.02)
	_expect(gestures.sample(0, Vector3.FORWARD * 5.0, true, true, 0.02).is_empty(), "tracking jumps are ignored")
	_expect(gestures.sample(0, Vector3.FORWARD, true, false, 0.02).is_empty(), "untracked hands cannot gesture")
	gestures.reset()
	for i in range(11):
		var event := gestures.sample(0, Vector3.RIGHT * i * 0.03, i < 6, true, 0.02)
		_expect(event.is_empty(), "crossing the surface cannot combine a partial swim stroke and wall")
	_expect(gestures.sample(0, Vector3.RIGHT * 0.4, false, true, 0.02).get("kind") == "wall", "a fresh air sweep works after leaving the water")
	for ticks in [30, 60, 90]:
		gestures.reset()
		var strokes := 0
		for i in range(ticks * 4):
			var elapsed: float = float(i) / ticks
			var cycle := int(elapsed)
			var reach := minf(fmod(elapsed, 1.0) / 0.25, 1.0)
			var x := 0.3 * (reach if cycle % 2 == 0 else 1.0 - reach)
			var event := gestures.sample(0, Vector3.RIGHT * x, true, true, 1.0 / ticks)
			if not event.is_empty():
				_expect(event.kind == "stroke", "water strokes never raise walls")
				strokes += 1
		_expect(strokes == 4, "one sideways stroke per second registers at every frame rate")
		gestures.reset()
		for i in range(ticks * 2):
			var at := Vector3(0.004 * sin(i), 0, 0.004 * cos(i))
			_expect(gestures.sample(0, at, true, true, 1.0 / ticks).is_empty(), "tracking tremor never accumulates into a stroke")


func _sweep(displacement: Vector3, wet := true, heading := Basis.IDENTITY) -> Dictionary:
	var gestures := Gestures.new()
	var result := {}
	for i in range(27):
		var at := heading * displacement * minf(i / 20.0, 1.0)
		var event := gestures.sample(0, at, wet, true, 0.02, heading)
		if not event.is_empty():
			result = event
	return result


func _water_hand_position(x: float, z: float, height: float) -> Vector3:
	var at := VR._origin.to_global(Vector3(x, 0, z))
	at.y = VR.immersion.player._ocean.get_height_at(at) + height
	return VR._origin.to_local(at)


func _set_hand(hand: int, at: Vector3, rotation := Basis.IDENTITY) -> void:
	trackers[hand].set_pose("grip", Transform3D(rotation, at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _place_hands(wet: bool) -> void:
	for i in range(2):
		_set_hand(i, _water_hand_position(-0.3 if i == 0 else 0.3, -0.5, -0.2 if wet else 0.3))
	await get_tree().process_frame
	await get_tree().process_frame
	VR.immersion.gestures.reset()


func _tracked_sweep(player, direction: Vector3, wet: bool, rotation := Basis.IDENTITY) -> void:
	await _place_hands(wet)
	var start: Vector3 = VR._hands[0].position
	for i in range(33):
		_set_hand(0, start + direction * 0.36 * minf(i / 20.0, 1.0), rotation)
		await get_tree().process_frame
		VR.immersion.combat(player, 1.0 / 60.0)
		_expect(player.vr_arms._hands[0].visible and player.vr_arms._hands[1].visible, "gestures keep both hands visible")


func _test_gesture_controls(player) -> void:
	var immersion = VR.immersion
	player.set_physics_process(false)
	immersion.cancel_gestures()
	var at: Vector3 = player.global_position
	var surface: float = player._ocean.get_height_at(at)
	at.y = surface - 0.1
	_expect(immersion.hand_touching_water(0, at), "hands below the actual surface touch water")
	at.y = surface + 0.1
	_expect(immersion.hand_touching_water(0, at), "small ripples do not flicker water contact")
	at.y = surface + 0.3
	_expect(not immersion.hand_touching_water(0, at), "raised hands are dry even when the player is in water")
	at.y = surface + 0.1
	_expect(not immersion.hand_touching_water(0, at), "lowering hands slightly does not flicker water contact")
	at.y = surface + 0.05
	_expect(immersion.hand_touching_water(0, at), "hands regain contact near the surface")
	player.stamina = 100.0
	player._water_power_cooldown_timer = 0.0
	await _tracked_sweep(player, Vector3.LEFT, true)
	_expect(immersion.swim_enabled and not player._water_wall_up, "upright sideways water strokes swim instead of raising a wall")
	_expect(player.stamina == 100.0 and player._water_power_cooldown_timer == 0.0, "swimming does not cast an attack")
	_set_hand(0, VR._hands[0].position, Basis(Vector3.BACK, 2.0))
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(immersion.swim_enabled, "changing wrist direction does not cancel the stroke window")
	for ticks in [30, 60, 90]:
		immersion.cancel_gestures()
		player.momentum = 0.0
		for i in range(ticks * 5):
			if i % ticks == 0:
				immersion.apply_gesture(player, {"kind": "stroke"}, player.global_position)
			immersion.combat(player, 1.0 / ticks)
			immersion.swim(player, 1.0 / ticks)
			_expect(immersion.swim_enabled, "one stroke per second keeps swimming active between strokes")
			if i == ticks - 1:
				_expect(is_equal_approx(player.momentum, 2.0), "swimming still gains only two momentum in the first second")
		_expect(is_equal_approx(player.momentum, 10.0), "full momentum still takes five seconds")
	Input.action_press("pad_move_down")
	immersion.swim(player, 0.02)
	_expect(player.dir.dot(VR._head.global_basis.z) > 0.0, "the stick can steer a swim stroke backwards")
	Input.action_release("pad_move_down")
	await _tracked_sweep(player, Vector3.RIGHT, false, Basis(Vector3.BACK, -PI / 2.0))
	_expect(not player._water_wall_up, "dry sideways motion without triggers never raises a wall")
	await _trigger(0, true)
	await _tracked_sweep(player, Vector3.LEFT, false)
	_expect(not player._water_wall_up, "one trigger cannot arm a wall")
	await _trigger(1, true)
	immersion.combat(player, 1.0 / 60.0)
	_expect(not player._water_wall_up and not immersion.swim_enabled, "both triggers stop rowing but require a fresh wall motion")
	await _tracked_sweep(player, Vector3.RIGHT, false)
	_expect(player._water_wall_up and not immersion.swim_enabled, "both triggers and a dry sideways motion raise a wall")
	var stamina: float = player.stamina
	immersion.apply_gesture(player, {"kind": "wave", "direction": Vector3.FORWARD, "distance": 0.5}, player.global_position)
	_expect(player.stamina == stamina, "a wall still blocks other attacks")
	await _tracked_sweep(player, Vector3.LEFT, true)
	immersion.swim(player, 0.02)
	_expect(not immersion.swim_enabled and not player.can_move and player.dir.is_zero_approx(), "both triggers block wet strokes and swimming thrust")
	await _trigger(0, false)
	immersion.combat(player, 1.0 / 60.0)
	_expect(not player._water_wall_up and not immersion.swim_enabled, "releasing either trigger drops the wall without resuming an old swim stroke")
	await _trigger(1, false)
	await _tracked_sweep(player, Vector3.LEFT, true)
	_expect(immersion.swim_enabled and not player._water_wall_up, "a water stroke switches from wall back to swimming")
	await _tracked_sweep(player, Vector3.FORWARD, true, Basis(Vector3.RIGHT, 0.8))
	_expect(player._water_power_cooldown_timer > 0.0, "forward water sweeps still launch attacks")
	immersion.cancel_gestures()
	player._water_power_cooldown_timer = 0.0
	await _place_hands(false)
	for i in range(90):
		immersion.combat(player, 1.0 / 60.0)
	_expect(not immersion.swim_enabled and not player._water_wall_up, "holding still never triggers swimming or a wall")


func _test_swimming(player) -> void:
	var immersion = VR.immersion
	var start: Vector3 = player.position
	var previous_fps := Engine.max_fps
	Engine.max_fps = 30
	player.position = Vector3(20, 7.5, 0)
	player.reset_physics_interpolation()
	trackers[0].set_input("primary", Vector2.ZERO)
	trackers[1].set_input("primary", Vector2.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	await _place_hands(true)
	_set_hand(0, _water_hand_position(-0.65, -0.5, -0.2))
	await get_tree().process_frame
	immersion.cancel_gestures()
	var forward: Vector3 = -Basis(Vector3.UP, VR._head.global_rotation.y).z
	player.momentum = 0.0
	player.stamina = 100.0
	player.set_physics_process(true)
	player.freeze = false
	var elapsed := 0.0
	var least_speed := INF
	while elapsed < 4.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var cycle := int(elapsed)
		var reach := minf(fmod(elapsed, 1.0) / 0.25, 1.0)
		var x := -0.65 + 0.3 * (reach if cycle % 2 == 0 else 1.0 - reach)
		_set_hand(0, _water_hand_position(x, -0.5, -0.2), Basis(Vector3.BACK, cycle * 0.7))
		if elapsed > 0.5:
			_expect(immersion.swim_enabled, "one sideways stroke per second sustains real swimming without a stick")
			least_speed = minf(least_speed, Vector2(player.linear_velocity.x, player.linear_velocity.z).length())
		_expect(not player._water_wall_up and player._water_power_cooldown_timer <= 0.0, "water strokes never cast walls or waves")
		_expect(player.vr_arms._hands[0].visible and player.vr_arms._hands[1].visible, "hands stay visible while swimming")
	_expect(least_speed > 0.2, "swimming stays smooth through the pause between strokes")
	_expect((player.position - Vector3(20, 7.5, 0)).dot(forward) > 2.0, "sideways strokes move forward in the headset direction")
	XRServer.remove_tracker(trackers[0])
	await get_tree().create_timer(0.1).timeout
	_expect(player.vr_arms._hands[0].visible and player.vr_arms._hands[1].visible, "brief occlusion keeps the last hand pose")
	XRServer.add_tracker(trackers[0])
	await get_tree().create_timer(1.5).timeout
	_expect(not immersion.swim_enabled, "swimming boost expires when strokes stop")
	var momentum: float = player.momentum
	await get_tree().create_timer(0.3).timeout
	_expect(player.momentum < momentum and player.momentum > 0.0, "stopping strokes coasts instead of stopping dead")
	player.freeze = true
	player.set_physics_process(false)
	player.linear_velocity = Vector3.ZERO
	for i in range(1200):
		immersion.swim(player, 1.0 / 60.0)
	_expect(is_zero_approx(player.momentum), "coasting eventually stops")
	player.position = start
	player.reset_physics_interpolation()
	immersion.cancel_gestures()
	Engine.max_fps = previous_fps
	await get_tree().process_frame


func _trigger(hand: int, pressed: bool) -> void:
	trackers[hand].set_input("trigger", 1.0 if pressed else 0.0)
	await get_tree().create_timer(0.2 if pressed else 0.04).timeout


func _test_pelts(player) -> void:
	var previous_fps := Engine.max_fps
	Engine.max_fps = 30
	await _place_hands(false)
	VR.immersion.cancel_gestures()
	player.stamina = 100.0
	player._water_pelt_cooldown_timer = 0.0
	player.set_physics_process(true)
	VR._head.rotation.x = 0.35
	var left_aim: Transform3D = trackers[0].get_pose("grip").transform
	left_aim.basis = Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.2)
	left_aim.origin.z -= 0.12
	trackers[0].set_pose("aim", left_aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	_set_hand(1, VR._hands[1].position, Basis(Vector3.UP, -0.4))
	await get_tree().process_frame
	await get_tree().process_frame
	var sequence: int = player._pelt_sequence
	await _trigger(0, true)
	_expect(player._pelt_sequence == sequence + 1, "left vr trigger fires a normal pelt")
	_expect(player.stamina < 100.0 and player._water_pelt_cooldown_timer > 0.0, "vr pelts use normal stamina and cooldown")
	var beam = player._ocean._active_pelts.get("%s_%d" % [player.name, player._pelt_sequence])
	_expect(is_instance_valid(beam), "vr trigger spawns the normal bubble beam")
	if is_instance_valid(beam):
		var pose: Transform3D = VR.immersion.hand_tip_transform(VR._hands[0])
		_expect(beam.origin.distance_to(pose.origin) < 0.001, "left trigger pelt starts at the left hand tip")
		_expect(beam.direction.is_equal_approx(-pose.basis.z.normalized()), "left trigger pelt follows controller aim instead of the headset")
	await get_tree().create_timer(player.water_pelt_cooldown + 0.1).timeout
	_expect(player._pelt_sequence == sequence + 1, "holding a trigger does not repeatedly fire")
	await _trigger(0, false)
	await _trigger(1, true)
	_expect(player._pelt_sequence == sequence + 2, "right trigger fires its own pelt")
	beam = player._ocean._active_pelts.get("%s_%d" % [player.name, player._pelt_sequence])
	_expect(is_instance_valid(beam), "right trigger spawns a beam")
	if is_instance_valid(beam):
		var pose: Transform3D = VR.immersion.hand_tip_transform(VR._hands[1])
		_expect(beam.origin.distance_to(pose.origin) < 0.001, "right trigger pelt starts at the right hand tip")
		_expect(beam.direction.is_equal_approx(-pose.basis.z.normalized()), "right trigger pelt follows grip when aim tracking is unavailable")
	await _trigger(1, false)
	await _trigger(0, true)
	_expect(player._pelt_sequence == sequence + 2, "alternating triggers cannot bypass the shared cooldown")
	await _trigger(0, false)
	await _trigger(1, false)
	var pelt_cost: float = player.water_pelt_stamina_cost
	player.water_pelt_stamina_cost = 20.0
	player.stamina = 10.0
	player._water_pelt_cooldown_timer = 0.0
	await _trigger(0, true)
	_expect(player._pelt_sequence == sequence + 2, "insufficient stamina blocks vr pelts")
	player.water_pelt_stamina_cost = pelt_cost
	await _trigger(0, false)
	player.stamina = 100.0
	trackers[0].set_input("trigger", 1.0)
	trackers[1].set_input("trigger", 1.0)
	await get_tree().create_timer(0.25).timeout
	_expect(player._pelt_sequence == sequence + 2 and not player._water_wall_up, "both triggers alone arm the wall without firing a pelt")
	_expect(not player._try_water_pelt(0), "an armed wall also blocks queued pelt attempts")
	VR.immersion.apply_gesture(player, {"kind": "wall"}, player.global_position)
	await get_tree().create_timer(0.1).timeout
	_expect(player._water_wall_up and player._pelt_sequence == sequence + 2, "water walls block trigger pelts")
	await _trigger(1, false)
	await _trigger(0, false)
	VR.immersion.cancel_gestures()
	trackers[0].set_input("trigger", 1.0)
	await get_tree().create_timer(0.04).timeout
	trackers[1].set_input("trigger", 1.0)
	await get_tree().create_timer(0.25).timeout
	_expect(player._pelt_sequence == sequence + 2, "slightly staggered trigger presses cancel the pending pelt")
	await _trigger(0, false)
	await _trigger(1, false)
	await get_tree().create_timer(0.2).timeout
	_expect(player._pelt_sequence == sequence + 2, "releasing the wall chord does not fire a delayed pelt")
	player.movement_locked = true
	await _trigger(0, true)
	_expect(player._pelt_sequence == sequence + 2, "movement lock blocks trigger pelts")
	player.movement_locked = false
	await _trigger(0, false)
	player._water_pelt_cooldown_timer = 0.0
	await _trigger(1, true)
	_expect(player._pelt_sequence == sequence + 3, "right trigger works independently after releasing both hands")
	await _trigger(1, false)
	VR._head.rotation.x = 0.0
	trackers[0].invalidate_pose("aim")
	player.set_physics_process(false)
	Engine.max_fps = previous_fps


func _test_cube_hands(player) -> void:
	var cube := get_tree().current_scene.get_node("PushCube") as RigidBody3D
	cube.get_node("Buoyancy").set_physics_process(false)
	cube.get_node("KingOfCube").set_physics_process(false)
	cube.gravity_scale = 0.0
	cube.global_position = player.global_position + Vector3(1.8, 0.7, 0)
	cube.rotation = Vector3.ZERO
	cube.linear_velocity = Vector3.ZERO
	cube.angular_velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start := cube.global_position
	VR.immersion.cancel_gestures()
	for offset in [-1.05, -0.8]:
		var tip: Vector3 = VR._origin.to_local(start + Vector3(offset, 0, 0))
		_set_hand(0, tip + Vector3(0, 0, 0.12))
		trackers[0].set_pose("aim", Transform3D(Basis.IDENTITY, tip), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await get_tree().process_frame
		await get_tree().process_frame
		VR.immersion.combat(player, 1.0 / 60.0)
	await get_tree().create_timer(0.2).timeout
	_expect(cube.global_position.x > start.x + 0.1, "tracked controller tip physically pushes the cube")
	trackers[0].invalidate_pose("aim")
	VR.immersion.cancel_gestures()
	cube.freeze = true
	await _place_hands(false)


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
