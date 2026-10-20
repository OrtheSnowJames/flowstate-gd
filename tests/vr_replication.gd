extends Node

var role := "host"
var client := 0
var spectator := 0
var checks: Dictionary = {}
var failed := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test="):
			role = argument.trim_prefix("--test=")
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	get_tree().create_timer(50).timeout.connect(func():
		push_error("FAIL vr replication timeout " + role)
		get_tree().quit(1))
	if role == "host":
		_expect(Net.host_game(18108) == OK, "hosting starts")
		await _until(func(): return client != 0)
		Net.start_round()
		await _until(func(): return Net._round_started and Net.arcade._body(1) != null)
		_publish(0.0)
		await _until(func(): return checks.has("ready"))
		await _until(func(): return not Net.arcade._body(client).replicated_vr_pose.is_empty())
		_expect(Net.arcade._body(client).replicated_vr_pose == _pose(0.2), "client hands reach host")
		print("READY_FOR_SPECTATOR")
		await _until(func(): return checks.get("ready", []).has(spectator) and spectator != 0)
		rpc("verify", client, 0.0, "late join")
		await _until(func(): return checks.get("late join", []).size() == 2)
		_publish(0.3)
		await get_tree().create_timer(0.3).timeout
		rpc("verify", client, 0.3, "moved hands")
		await _until(func(): return checks.get("moved hands", []).size() == 2)
		Net.arcade._body(1).replicated_vr_pose = []
		await get_tree().create_timer(0.3).timeout
		rpc("verify_stopped")
		await _until(func(): return checks.get("stopped", []).size() == 2)
		rpc("finish")
		finish()
		return
	Net._connect_flow_active = true
	_expect(Net.join_game("127.0.0.1", 18108) == OK, "joining starts")
	await multiplayer.connected_to_server
	rpc_id(1, "register", role)
	if role == "spectator":
		await _until(func(): return Net._connection_game_in_progress)
		_choose_spectate()
		await Net._show_game_in_progress_prompt()
	await _until(func(): return Net.arcade._body(1) != null)
	if role == "client":
		await _until(func(): return Net.arcade._body(multiplayer.get_unique_id()) != null)
		_publish(0.2)
	else:
		VR.start(true)
		await VR.enter_immersive()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(VR.immersion.player == null and not VR.immersion.blur.visible, "late spectator has a sharp immersive view")
	rpc_id(1, "checked", "ready")


func _publish(offset: float) -> void:
	var body = Net.arcade._body(multiplayer.get_unique_id())
	body.freeze = true
	body.set_physics_process(false)
	body.vr_arms.set_process(false)
	body.replicated_vr_pose = _pose(offset)


func _pose(offset: float) -> Array:
	return [Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)),
		Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(-0.3, 0.1 + offset, -0.4)),
		Transform3D(Basis(Vector3.UP, -0.7), Vector3(0.3, 0.1, -0.4 - offset)), 3]


@rpc("authority", "reliable")
func verify(client_id: int, offset: float, stage: String) -> void:
	var host = Net.arcade._body(1)
	_expect(host.replicated_vr_pose == _pose(offset), stage + " host poses replicate")
	_expect(host.vr_arms.visible and host.get_node("blockbench_export").visible, stage + " other players see body and arms")
	_expect(not host.vr_arms._original_arms.is_empty(), "original arm meshes found")
	for arm in host.vr_arms._original_arms:
		_expect(not arm.visible, "original arms replaced")
	for i in range(2):
		var original: Node3D = host.vr_arms._original_arms[i]
		var copy: Node3D = host.vr_arms._hands[i].get_node("Arm")
		for mesh in host._mesh_instances_in(original):
			var tracked_mesh: MeshInstance3D = copy.get_node(original.get_path_to(mesh))
			_expect(tracked_mesh.mesh == mesh.mesh and tracked_mesh.is_visible_in_tree(), "remote tracked arms use the player model")
	for i in range(2):
		var transmitted: Transform3D = _pose(offset)[i + 1]
		var displayed: Transform3D = host.vr_arms._hands[i].transform
		_expect(displayed.origin.distance_to(transmitted.origin + Vector3(0, 0.1, -0.6)) < 0.02, "remote arms sit forward and above the tracked pose")
		_expect(displayed.basis.is_equal_approx(transmitted.basis), "remote offset preserves hand orientation")
	_verify_lowered_arms(host)
	_expect(Net.arcade._body(client_id).replicated_vr_pose == _pose(0.2), stage + " client poses replicate")
	rpc_id(1, "checked", stage)


func _verify_lowered_arms(body) -> void:
	var arms = body.vr_arms
	var saved_pose: Array = arms.pose
	var saved_display: Array = arms._display
	var saved_transform: Transform3D = body.transform
	for yaw in [0.0, PI / 2.0, PI, -PI / 2.0]:
		body.rotation = Vector3(0, yaw, 0)
		for wrist_angle in [-PI / 2.0, 0.0, PI / 2.0]:
			arms.pose = [Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)),
				Transform3D(Basis(Vector3.RIGHT, wrist_angle), Vector3(-0.3, -0.2, 0)),
				Transform3D(Basis(Vector3.RIGHT, wrist_angle), Vector3(0.3, -0.2, 0)), 3]
			arms._display = []
			arms._process(0.0)
			for i in range(2):
				var tracked: Vector3 = body.global_transform * arms.pose[i + 1].origin
				var shift: Vector3 = arms._hands[i].global_position - tracked
				var forward: Vector3 = -body.global_basis.z.normalized()
				_expect(shift.distance_to(forward * 0.6 + Vector3.UP * 0.1) < 0.001,
					"lowered arms shift along player facing regardless of wrist angle")
	body.transform = saved_transform
	arms.pose = saved_pose
	arms._display = saved_display
	arms._process(0.0)


@rpc("authority", "reliable")
func verify_stopped() -> void:
	var host = Net.arcade._body(1)
	_expect(host.replicated_vr_pose.is_empty() and not host.vr_arms.visible, "vr exit replicated")
	for arm in host.vr_arms._original_arms:
		_expect(arm.visible, "animated arms restored")
	rpc_id(1, "checked", "stopped")


@rpc("any_peer", "reliable")
func register(value: String) -> void:
	if value == "client":
		client = multiplayer.get_remote_sender_id()
	else:
		spectator = multiplayer.get_remote_sender_id()


@rpc("any_peer", "reliable")
func checked(stage: String) -> void:
	if not checks.has(stage):
		checks[stage] = []
	checks[stage].append(multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func finish() -> void:
	if VR.active:
		VR.stop()
	print(("FAIL" if failed else "PASS") + " vr replication " + role)
	get_tree().quit(1 if failed else 0)


func _choose_spectate() -> void:
	await _until(func(): return Transition.has_node("DisconnectPrompt"))
	Transition.get_node("DisconnectPrompt")._choose(true)


func _until(condition: Callable) -> void:
	while not condition.call():
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + role + " " + message)
