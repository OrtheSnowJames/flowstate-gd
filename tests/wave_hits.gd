extends Node

class Target extends Node3D:
	var hits := 0
	var damage := 0.0

	func take_stamina_damage(amount: float) -> void:
		hits += 1
		damage += amount

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Net._round_over = true
	var player := Net._players_root().get_node("1")
	player.freeze = true
	player.set_physics_process(false)
	var ocean := get_parent().get_node("water base")
	ocean.set_physics_process(false)
	ocean._tracked.clear()
	var origin := Vector3(0, ocean.global_position.y, 0)
	var near_target := Target.new()
	var far_target := Target.new()
	get_parent().add_child(near_target)
	get_parent().add_child(far_target)
	near_target.global_position = origin + Vector3.RIGHT
	far_target.global_position = origin + Vector3.RIGHT * 1.8
	for body in [far_target, near_target]:
		ocean._tracked[body.get_instance_id()] = {"body": body, "r": 0.35}
	for method in ["send_wave", "send_attack_wave"]:
		var previous_hits := near_target.hits
		ocean.call(method, origin, Vector3.RIGHT, 1.0, player, true, 5.0, 5.0)
		_expect(near_target.hits == previous_hits + 1, method + " damages the nearest target once")
		_expect(far_target.hits == 0, method + " cannot pass through the first target")
		_expect(ocean._active_waves.is_empty(), method + " leaves no traveling wave after a hit")
		_expect(ocean.get_active_waves().is_empty(), method + " cannot restore a consumed wave for a spectator")
	var hit: Dictionary = ocean.resolve_wave_hit(origin, Vector3.RIGHT, 1.0, player)
	var hits_before := near_target.hits
	ocean._tracked.clear()
	near_target.global_position += Vector3.FORWARD * 10.0
	for method in ["send_wave", "send_attack_wave"]:
		ocean.call(method, origin, Vector3.RIGHT, 1.0, player, false, 5.0, 5.0, hit)
		_expect(ocean._active_waves.is_empty(), method + " uses the caster hit even when the target moved locally")
	_expect(near_target.hits == hits_before, "visual replicas never apply damage twice")
	near_target.free()
	ocean.send_wave(origin, Vector3.RIGHT, 1.0, player, false, 5.0, 5.0, hit)
	_expect(ocean._active_waves.is_empty(), "consumed wave stays gone even when the target despawns")
	var miss: Dictionary = ocean.resolve_wave_hit(origin, Vector3.RIGHT, 1.0, player)
	ocean._tracked[far_target.get_instance_id()] = {"body": far_target, "r": 0.35}
	ocean.send_wave(origin, Vector3.RIGHT, 1.0, player, false, 5.0, 5.0, miss)
	_expect(ocean._active_waves.size() == 1, "caster miss does not become a different local hit")
	_expect(far_target.hits == 0, "miss does not damage a target on a visual replica")
	await get_tree().create_timer(1.0).timeout
	_expect(ocean._active_waves.is_empty(), "missed wave still expires normally")
	ocean._tracked.clear()
	ocean.send_attack_wave(origin, Vector3.RIGHT, 1.0, player)
	_expect(ocean._active_waves.size() == 1, "missed close range attack still draws a wave")
	await get_tree().create_timer(0.7).timeout
	_expect(ocean._active_waves.is_empty(), "close range miss expires normally")
	print("FAIL wave hits" if failed else "PASS wave hits")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
