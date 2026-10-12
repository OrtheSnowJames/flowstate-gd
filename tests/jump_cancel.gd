extends Node

var failed := false
var player: RigidBody3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Net._round_over = true
	player = Net._players_root().get_node("1")
	player.freeze = true
	player.set_physics_process(false)
	var cube: RigidBody3D = get_parent().get_node("PushCube")
	cube.freeze = true
	cube.position = Vector3(12, 7.6, 0)
	_reset()
	_expect(not player._try_jump_cancel(), "shift without a jump gives no boost")
	player._jump(false)
	_expect(not player._try_jump_cancel(), "rejected jump cannot be cancelled")
	player._jump(true)
	_expect(player._try_jump_cancel(), "water jump can be cancelled")
	_expect(is_equal_approx(player.momentum, player.jump_cancel_momentum), "cancel grants large momentum boost")
	_expect(is_equal_approx(player.stamina, player.max_stamina - player.jump_cancel_stamina_cost), "cancel spends stamina once")
	_expect(is_zero_approx(player.linear_velocity.y), "cancel stops upward motion")
	_expect(player.linear_velocity.z < -8.0, "cancel bursts forward without movement input")
	_expect(not player._try_jump_cancel(), "same jump cannot be cancelled twice")
	player._jump(true)
	_expect(not player._try_jump_cancel(), "cancel keeps the jump cooldown")
	_expect(is_equal_approx(player.stamina, player.max_stamina - player.jump_cancel_stamina_cost), "failed repeat costs nothing")
	_reset()
	player.stamina = player.jump_cancel_stamina_cost - 1.0
	player._jump(true)
	var launch_speed := player.linear_velocity.y
	_expect(not player._try_jump_cancel(), "low stamina rejects cancel")
	_expect(player.linear_velocity.y == launch_speed and player.momentum == 0.0, "rejected cancel leaves jump intact")
	_expect(player.stamina == player.jump_cancel_stamina_cost - 1.0, "rejected cancel costs no stamina")
	_reset()
	player._jump(true)
	player.position.y = player._water_height() + player.body_half_height + 0.1
	_expect(not player._try_jump_cancel(), "cannot cancel after leaving water")
	player.position.y = 7.0
	_expect(not player._try_jump_cancel(), "returning to water does not reopen cancel")
	_reset()
	player.position.y = player._water_height() + player.body_half_height + 0.1
	player._jump(true)
	player.position.y = 7.0
	_expect(not player._try_jump_cancel(), "dry jumps do not arm a water cancel")
	_reset()
	player._jump(true)
	player.linear_velocity.y = -1.0
	_expect(not player._try_jump_cancel(), "falling jump cannot be cancelled")
	_reset()
	player.position = Vector3(10, 7, 0)
	player.momentum = 0.0
	player._jump(false)
	_expect(player._try_jump_cancel(), "cube water jumps can be cancelled")
	_reset()
	player._jump(true)
	player.momentum = player.max_momentum - 1.0
	player._water_wall_up = true
	Input.action_press("back")
	_expect(player._try_jump_cancel(), "backstroke cancel works")
	_expect(player.linear_velocity.z > 8.0, "cancel follows backstroke direction")
	_expect(player.momentum == player.max_momentum, "momentum stays capped")
	_expect(player.stamina == player.max_stamina - player.jump_cancel_stamina_cost, "water wall cannot discount cancel cost")
	player._water_wall_up = false
	Input.action_release("back")
	for blocked in ["movement_locked", "_unconscious"]:
		_reset()
		player._jump(true)
		player.set(blocked, true)
		_expect(not player._try_jump_cancel(), blocked + " blocks cancel")
		player.set(blocked, false)
	_reset()
	player._jump(true)
	Net._input_blocked_by_menu = true
	_expect(not player._try_jump_cancel(), "menus block cancel")
	Net._input_blocked_by_menu = false
	_reset()
	player._jump(true)
	Net._spectator_mode = true
	_expect(not player._try_jump_cancel(), "spectators cannot cancel")
	Net._spectator_mode = false
	_reset()
	player._jump(true)
	player.set_multiplayer_authority(2, false)
	_expect(not player._try_jump_cancel(), "remote players ignore local cancel")
	player.set_multiplayer_authority(1, false)
	_reset()
	await _test_input()
	print("FAIL jump cancel" if failed else "PASS jump cancel")
	get_tree().quit(1 if failed else 0)


func _test_input() -> void:
	Input.action_press("swim_key")
	await get_tree().physics_frame
	await get_tree().physics_frame
	player._jump(true)
	player._physics_process(1.0 / 60.0)
	_expect(player._jump_cancel_available and player.linear_velocity.y > 0.0, "holding shift before jump does not cancel")
	Input.action_release("swim_key")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_press("swim_key")
	await get_tree().physics_frame
	player.linear_velocity.y = 5.0
	player._physics_process(1.0 / 60.0)
	_expect(not player._jump_cancel_available and player.linear_velocity.y == 0.0, "fresh shift press cancels through physics input")
	_expect(player.momentum > 7.5, "swim processing preserves cancel momentum")
	Input.action_release("swim_key")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_reset()
	player.position = Vector3(10, 7, 0)
	player.momentum = 0.0
	player.freeze = false
	player.set_physics_process(true)
	player.reset_physics_interpolation()
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	_expect(player._jump_cancel_available and player._submersion() > 0.0, "live jump opens underwater cancel window")
	Input.action_press("forward")
	Input.action_press("swim_key")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(not player._jump_cancel_available and player.momentum > 7.5, "live jump then shift grants momentum")
	_expect(player.stamina < player.max_stamina - 9.0, "live cancel spends stamina")
	var start := player.position
	for tick in range(8):
		await get_tree().physics_frame
	_expect(player.position.z < start.z - 0.5, "cancel makes a visible horizontal burst")
	Input.action_release("forward")
	Input.action_release("swim_key")


func _reset() -> void:
	player.position = Vector3(2, 7, 0)
	player.rotation = Vector3.ZERO
	player.linear_velocity = Vector3.ZERO
	player.momentum = player.max_momentum
	player.stamina = player.max_stamina
	player._jump_cooldown_timer = 0.0
	player._jump_cancel_available = false
	player.movement_locked = false
	player._unconscious = false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
