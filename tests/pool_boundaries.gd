extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Net._round_over = true
	var player: RigidBody3D = Net._players_root().get_node("1")
	var walls := get_parent().get_node("walls")
	_expect(walls is StaticBody3D, "barriers have a physics body")
	player.set_physics_process(false)
	get_parent().get_node("PushCube").freeze = true
	await get_tree().physics_frame
	var space := player.get_world_3d().direct_space_state
	for height in [9.5, 15.0, 25.0]:
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var start := Vector3(direction.x * 24, height, direction.z * 19)
			var query := PhysicsRayQueryParameters3D.create(start, start + direction * 40, 1, [player.get_rid()])
			var hit := space.intersect_ray(query)
			_expect(hit.get("collider") == walls, "barrier blocks direction %s at height %s" % [direction, height])
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK,
		Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
		player.freeze = true
		player.position = Vector3(direction.x * 23, 12, direction.z * 18)
		player.linear_velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		player.freeze = false
		player.sleeping = false
		player.linear_velocity = direction.normalized() * 24 + Vector3.UP * player.cube_jump_speed
		for tick in range(60):
			await get_tree().physics_frame
			var pos := player.position
			if absf(pos.x) > 26.5 or pos.z < -21.608849 or pos.z > 21.547321:
				_expect(false, "boosted player escaped toward %s at %s" % [direction, pos])
				break
	print("FAIL pool boundaries" if failed else "PASS pool boundaries")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
