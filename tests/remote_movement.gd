extends Node3D

const PLAYER := preload("res://water/player.tscn")
var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var remote := _make_player(2)
	var sync: MultiplayerSynchronizer = remote.get_node("MultiplayerSynchronizer")
	_expect(is_equal_approx(sync.replication_interval, 0.1), "movement updates run at ten hertz")
	for name in ["MultiplayerSynchronizer", "SpawnSynchronizer"]:
		var config: SceneReplicationConfig = remote.get_node(name).replication_config
		_expect(config.get_properties().has(NodePath(".:replicated_transform")), "spawn and movement use transform snapshots")
		_expect(not config.get_properties().has(NodePath(".:position")), "position is not overwritten directly")

	# simulate ten packets a second with sixty rendered frames
	var previous := remote.position.x
	for frame in range(60):
		if frame % 6 == 0:
			var target := Transform3D(Basis.IDENTITY, Vector3((frame / 6 + 1) * 0.5, 0, 0))
			remote.replicated_transform = target
			_expect(is_equal_approx(remote.position.x, previous), "packets do not snap ordinary movement")
		remote._interpolate_remote_movement(1.0 / 60.0)
		_expect(remote.position.x > previous, "movement continues between packets")
		_expect(remote.position.x - previous < 0.3, "movement has no packet sized steps")
		_expect(remote.position.x <= remote.replicated_transform.origin.x, "movement does not overshoot")
		previous = remote.position.x

	remote.replicated_transform = Transform3D(Basis.IDENTITY, Vector3(5.5, 0, 0))
	remote._interpolate_remote_movement(0.05)
	var late := _make_player(3, remote.replicated_transform)
	_expect(late.transform.is_equal_approx(remote.replicated_transform), "late join snaps to latest snapshot")
	_expect(late.position.x > remote.position.x, "late join does not inherit interpolation lag")
	var start := Transform3D(Basis(Vector3.UP, deg_to_rad(178)), Vector3.ZERO)
	var target := Transform3D(Basis(Vector3.UP, deg_to_rad(-178)), Vector3(3, 0, 0))
	_start_motion(remote, start, target)
	remote._interpolate_remote_movement(0.04)
	_expect(absf(rad_to_deg(remote.rotation.y)) > 178.0, "rotation takes the short path across wraparound")
	_start_motion(remote, start, target)
	for frame in range(6):
		remote._interpolate_remote_movement(1.0 / 30.0)
	var at_thirty: Transform3D = remote.transform
	_start_motion(remote, start, target)
	for frame in range(24):
		remote._interpolate_remote_movement(1.0 / 120.0)
	_expect(remote.transform.is_equal_approx(at_thirty), "smoothing is frame rate independent")
	for frame in range(120):
		remote._interpolate_remote_movement(1.0 / 60.0)
	_expect(remote.position.distance_to(target.origin) < 0.001, "movement settles after packets stop")
	var teleport := Transform3D(Basis.IDENTITY, Vector3(40, 0, 0))
	remote.replicated_transform = teleport
	_expect(remote.transform.is_equal_approx(teleport), "large teleports snap immediately")
	_start_motion(remote, Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(0, -2, 0)))
	for frame in range(6):
		remote._interpolate_remote_movement(1.0 / 60.0)
		_expect(is_equal_approx(remote.position.y, -2.0 * (frame + 1) / 6.0), "falling advances evenly between packets")
	var local := _make_player(1)
	local.position = Vector3(2, 1, 0)
	local._interpolate_remote_movement(0.1)
	_expect(local.position == Vector3(2, 1, 0), "local movement stays immediate")
	_expect(local.replicated_transform == local.transform, "owner sends current transform")
	await get_tree().process_frame
	await get_tree().process_frame
	print("PASS remote movement interpolation" if not failed else "FAIL remote movement interpolation")
	get_tree().quit(1 if failed else 0)


func _make_player(id: int, initial := Transform3D.IDENTITY) -> Node3D:
	var player: Node3D = PLAYER.instantiate()
	player.name = str(id)
	player.replicated_transform = initial
	add_child(player)
	player.freeze = true
	player.set_process(false)
	player.set_physics_process(false)
	return player


func _start_motion(player: Node3D, start: Transform3D, target: Transform3D) -> void:
	player._has_remote_transform = false
	player.replicated_transform = start
	player.replicated_transform = target


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
