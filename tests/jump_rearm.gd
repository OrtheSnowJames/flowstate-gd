extends Node

var failed := false
const Movement = preload("res://water/player/movement.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player = Net._players_root().get_node("1")
	player.freeze = true
	player.set_physics_process(false)
	Net._add_player(2)
	var opponent = Net._players_root().get_node("2")
	opponent.freeze = true
	opponent.set_physics_process(false)
	for mode in [Net.GameMode.NORMAL, Net.GameMode.ARCADE]:
		Net.net_sync_game_mode(mode)
		player.position = Vector3(-10, 7.655, 0)
		player.linear_velocity = Vector3.ZERO
		player._jump_cooldown_timer = 0.0
		player.momentum = player.max_momentum
		Movement._refresh_jump(player)
		player._jump(true)
		_expect(player.linear_velocity.y > 0, "initial water jump")
		player._jump_cooldown_timer = 0.0
		Movement._refresh_jump(player)
		_expect(player._jump_spent, "rising through water does not rearm")
		player.position.y = 20
		opponent.position = Vector3(-10, 18, 0)
		await get_tree().physics_frame
		for i in range(4):
			player.linear_velocity = Vector3.ZERO
			player.momentum = player.max_momentum
			player._jump_cooldown_timer = 0.0
			Movement._refresh_jump(player)
			player._jump(true)
			_expect(player.linear_velocity.y == 0, "hovering over an opponent cannot grant jumps")
		player._jump_spent = false
		player._jump(true)
		_expect(player.linear_velocity.y == 0, "airborne jump rejected even without spent flag")
		player.position.y = 7.655
		player.linear_velocity = Vector3.DOWN
		Movement._refresh_jump(player)
		player._jump(true)
		_expect(player.linear_velocity.y > 0, "water reentry restores jumping")
	print("FAIL jump rearm" if failed else "PASS jump rearm")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
