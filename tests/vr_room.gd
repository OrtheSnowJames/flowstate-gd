extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	_expect(VR.is_standalone_quest("Android", "Quest 3", ""), "quest detection")
	_expect(not VR.is_standalone_quest("Windows", "Quest 3", "Oculus"), "quest link is unrestricted pcvr")
	_expect(not VR.is_standalone_quest("Android", "Pixel", ""), "other android devices unrestricted")
	var saved: bool = Settings._performance_mode
	Settings.performance_mode = false
	VR.quest_standalone = true
	_expect(Settings.performance_mode, "quest performance forced")
	Settings.performance_mode = false
	_expect(Settings.performance_mode, "quest performance cannot be disabled")
	_expect(Net.host_game(18107) == ERR_UNAVAILABLE, "quest hosting rejected")
	_expect(not Net.is_online(), "rejected hosting leaves networking unchanged")
	VR.quest_standalone = false
	_expect(not Settings.performance_mode, "pcvr performance is optional")
	Settings._performance_mode = saved
	_expect(VR.start(true), "room preview starts")
	_expect(VR.room_view.own_world_3d, "vr room separate from game")
	var original_head: Transform3D = VR._head.transform
	var original_origin: Transform3D = VR._origin.transform
	var seat: Vector3 = VR._room.get_node("SeatEye").global_position
	for yaw in [0.0, 1.4, -2.3, PI]:
		VR._head.transform = Transform3D(Basis.from_euler(Vector3(0.2, yaw, 0.1)), Vector3(7, 2.1, -9))
		VR._place_in_room(VR._head.transform)
		_expect(VR._head.global_position.is_equal_approx(seat), "offset headset starts at couch")
		var forward: Vector3 = -VR._head.global_basis.z
		forward.y = 0.0
		_expect(forward.normalized().dot(Vector3.FORWARD) > 0.999, "headset faces tv regardless of tracking yaw")
		VR._head.position.x += 0.2
		_expect(is_equal_approx(VR._head.global_position.distance_to(seat), 0.2), "physical leaning still moves the view")
	VR._request_room_center()
	_expect(VR._room_needs_center, "system recenter requests couch placement")
	VR._center_room_from_tracking()
	_expect(VR._room_needs_center, "centering waits for tracked headset")
	var tracker := XRPositionalTracker.new()
	tracker.type = XRServer.TRACKER_HEAD
	tracker.name = "head"
	var tracked_head := Transform3D(Basis(Vector3.UP, 1.2), Vector3(-8, 1.2, 6))
	tracker.set_pose("default", tracked_head, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	VR._head.transform = tracker.get_pose("default").get_adjusted_transform()
	VR._center_room_from_tracking()
	_expect(not VR._room_needs_center, "first tracked pose completes centering")
	_expect(VR._head.global_position.is_equal_approx(seat), "tracking pipeline places headset at couch")
	XRServer.remove_tracker(tracker)
	VR._head.transform = original_head
	VR._origin.transform = original_origin
	var screen = VR.room_view.get_node("VrRoom/GameScreen")
	_expect(screen.material_override.albedo_texture == get_tree().root.get_texture(), "tv uses live game viewport")
	await get_tree().create_timer(1.5).timeout
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		var picture := VR.room_view.get_texture().get_image()
		picture.save_png("/tmp/flowstate-vr-room.png")
		_expect(not picture.is_empty(), "room renders")
	var room_id := VR.room_view.get_instance_id()
	Net.start_solo_play()
	while not Net._round_started or Net.arcade._body(1) == null:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_expect(VR.room_view.get_instance_id() == room_id, "room persists across game scenes")
	_expect(VR.room_view.world_3d != get_tree().root.world_3d, "pool stays out of the vr room")
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		VR.room_view.get_texture().get_image().save_png("/tmp/flowstate-vr-game.png")
	VR.stop()
	_expect(not VR.active, "vr stops cleanly")
	print("FAIL vr room" if failed else "PASS vr room")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
