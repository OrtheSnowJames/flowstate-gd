extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Net._round_over = true
	var player := Net._players_root().get_node("1")
	var cube: RigidBody3D = get_parent().get_node("PushCube")
	cube.freeze = true
	cube.position = Vector3(12, 7.6, 0)
	player.freeze = true
	player.set_physics_process(false)
	player.position = Vector3(10, 7, 0)
	player.momentum = 0.0
	player._jump(false)
	_expect(is_equal_approx(player.linear_velocity.y, player.cube_jump_speed), "nearby water jump works without momentum")
	player.linear_velocity = Vector3.ZERO
	player._jump(false)
	_expect(player.linear_velocity == Vector3.ZERO, "boost respects cooldown")
	player._jump_cooldown_timer = 0.0
	player.position = Vector3(2, 7, 0)
	player.momentum = player.max_momentum
	player._jump(true)
	_expect(is_equal_approx(player.linear_velocity.y, player.jump_speed), "normal jump stays unchanged away from cube")
	player._jump_cooldown_timer = 0.0
	player.linear_velocity = Vector3.ZERO
	player._jump(false)
	_expect(player.linear_velocity == Vector3.ZERO, "deep water away from cube does not grant a jump")
	player.position = Vector3(10, 10, 0)
	_expect(not player._can_cube_jump(), "airborne player cannot get another cube boost")
	player.position = Vector3(10, 7, 0)
	cube.position.x = 20
	_expect(not player._can_cube_jump(), "range follows the moving cube")
	cube.position.x = 12
	cube.name = "MissingCube"
	_expect(not player._can_cube_jump(), "missing cube leaves normal jumping alone")
	cube.name = "PushCube"
	player.freeze = false
	player.set_physics_process(true)
	player.momentum = 0.0
	player.linear_velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	var highest_feet: float = player.position.y - player.body_half_height
	var captured := false
	for tick in range(100):
		await get_tree().physics_frame
		highest_feet = maxf(highest_feet, player.position.y - player.body_half_height)
		if not captured and highest_feet > cube.position.y + 2.8 and DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			get_viewport().get_texture().get_image().save_png("/tmp/flowstate-cube-jump.png")
			captured = true
	_expect(highest_feet > cube.position.y + 0.8 + 2.0, "boost clears the cube with room to land")
	print("cube jump highest feet ", highest_feet, " cube top ", cube.position.y + 0.8)
	print("PASS cube jump" if not failed else "FAIL cube jump")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
