extends Node

class Target extends StaticBody3D:
	var damage := 0.0
	var body_half_height := 1.0

	func take_stamina_damage(amount: float) -> void:
		damage += amount

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _target(position: Vector3) -> Target:
	var target := Target.new()
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 2.0
	shape.radius = 0.5
	collision.shape = shape
	target.add_child(collision)
	get_parent().add_child(target)
	target.add_to_group("player")
	target.global_position = position
	return target


func _run() -> void:
	var player := Net._players_root().get_node("1")
	player.freeze = true
	player.set_physics_process(false)
	var ocean := get_parent().get_node("water base")
	ocean.set_physics_process(false)
	var cube := get_parent().get_node("PushCube")
	cube.freeze = true
	cube.global_position = Vector3(12, 10, 0)
	Net._round_over = false
	Net.round_state = Net.RoundState.PLAYING
	var target := _target(Vector3(12, 16, 0))
	var behind := _target(Vector3(15, 17, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var origin := Vector3(6, 14, 0)
	ocean.send_water_pelt(origin, (target.global_position - origin).normalized(), player, "up")
	await get_tree().create_timer(0.4).timeout
	_expect(target.damage == 10.0, "upward shot deals ten stamina damage")
	_expect(behind.damage == 0.0, "beam stops at the first player")
	_expect(ocean.get_active_pelts().is_empty(), "hit removes the beam")
	target.global_position = Vector3(12, 11.82, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	origin = Vector3(6, 11, 0)
	ocean.send_water_pelt(origin, (target.global_position - origin).normalized(), player, "cube")
	await get_tree().create_timer(0.4).timeout
	_expect(target.damage == 30.0, "standing on the cube doubles damage")
	origin = Vector3(6, 10, 0)
	ocean.send_water_pelt(origin, Vector3.RIGHT, player, "blocked")
	await get_tree().create_timer(0.4).timeout
	_expect(ocean.get_active_pelts().is_empty(), "solid cube blocks the beam")
	_expect(target.damage == 30.0, "blocked beam deals no damage")
	ocean.net_remove_pelt("consumed")
	ocean.send_water_pelt(Vector3(0, 20, 0), Vector3.UP, player, "consumed")
	_expect(ocean.get_active_pelts().is_empty(), "late cast cannot restore a consumed beam")
	ocean.restore_active_pelts([["snapshot", Vector3(0, 20, 0), Vector3.UP, 3.0, player.get_path()]])
	var beam = ocean._active_pelts.get("snapshot")
	_expect(beam != null and beam.global_position.is_equal_approx(Vector3(0, 23, 0)), "snapshot preserves upward direction and distance")
	await get_tree().create_timer(1.1).timeout
	_expect(ocean.get_active_pelts().is_empty(), "miss expires at maximum range")
	_expect(InputMap.has_action("water_pelt"), "input binding exists")
	player.movement_locked = false
	player.stamina = 100.0
	_expect(player._try_water_pelt(), "ready player can cast")
	_expect(player.stamina == 95.0, "casting costs five stamina")
	_expect(not player._try_water_pelt(), "cooldown prevents repeat casts")
	player._water_pelt_cooldown_timer = 0.0
	player.stamina = 4.0
	_expect(not player._try_water_pelt(), "insufficient stamina prevents casting")
	if OS.get_environment("FLOWSTATE_PELT_SCREENSHOT") != "":
		var camera := Camera3D.new()
		get_parent().add_child(camera)
		camera.global_position = Vector3(4, 18, 7)
		camera.look_at(Vector3(7, 16, 0))
		camera.make_current()
		ocean.send_water_pelt(Vector3(3, 14, 0), Vector3(1, 0.6, 0).normalized(), player, "preview", 5.0)
		ocean._active_pelts.preview.set_physics_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(OS.get_environment("FLOWSTATE_PELT_SCREENSHOT"))
	print("FAIL water pelt" if failed else "PASS water pelt")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
