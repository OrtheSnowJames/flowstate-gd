extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := Net._players_root().get_node("1")
	var ocean := get_parent().get_node("water base")
	player.freeze = true
	player.set_physics_process(false)
	player.movement_locked = false
	player.position = Vector3(0, 7.655, 0)
	player.stamina = 100.0
	ocean.set_physics_process(false)
	ocean._tracked.clear()
	_expect(InputMap.has_action("water_counter"), "counter binding exists")
	_expect(player._try_water_counter(), "counter casts")
	_expect(player.stamina == 50.0, "counter costs exactly fifty stamina")
	_expect(player._water_wall_up and ocean._walls.size() == 1, "counter raises a wall")
	_expect(ocean.get_active_waves().size() == 1, "counter fires water power")
	_expect(not player._try_water_counter(), "counter cannot stack")
	_expect(not player._try_water_pelt(), "counter wall blocks other attacks")
	player._update_water_counter(0.99)
	_expect(player._water_wall_up, "counter wall lasts almost a second")
	_expect(player.stamina == 50.0, "counter wall has no extra stamina cost")
	player._update_water_counter(0.02)
	_expect(not player._water_wall_up and ocean._walls.is_empty(), "counter wall expires after one second")
	player.stamina = 49.0
	_expect(not player._try_water_counter() and player.stamina == 49.0, "insufficient stamina rejects counter")
	player.stamina = 100.0
	player._cast_water_wall(Vector3(0, 7.655, 0), Vector3.RIGHT, 1.0)
	_expect(not player._try_water_counter(), "normal wall still blocks casts")
	player._cast_water_wall_stop()
	Input.action_press("water_counter")
	Input.action_press("water_wall")
	Input.action_press("water_power")
	player.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.set_physics_process(false)
	_expect(player._water_counter_timer > 0.9 and absf(player.stamina - 50.0) < 0.2, "counter input takes priority without double charging")
	Input.action_release("water_counter")
	Input.action_release("water_wall")
	Input.action_release("water_power")
	Net._input_blocked_by_menu = true
	player._physics_process(1.01)
	_expect(not player._water_wall_up, "counter expires while a menu blocks input")
	Net._input_blocked_by_menu = false
	print("FAIL water counter" if failed else "PASS water counter")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
