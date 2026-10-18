extends Node

var failed := false
var combat: Node
var first: Node3D
var second: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	combat = Net.arcade
	combat.set_physics_process(false)
	Net.net_sync_game_mode(Net.GameMode.ARCADE)
	Net.round_state = Net.RoundState.PLAYING
	Net._round_over = false
	Net._add_player(2)
	first = combat._body(1)
	second = combat._body(2)
	first.team = 0
	second.team = 1
	for player in [first, second]:
		player.freeze = true
		player.movement_locked = false
		player.set_physics_process(false)
	get_parent().get_node("water base").set_physics_process(false)
	await get_tree().physics_frame
	_expect(Net.game_mode == Net.GameMode.ARCADE, "arcade survives mode sync")
	_expect(first.max_stamina_per_mode(Net.game_mode) == 200, "arcade stamina preserved")
	_reset()
	_dash_pair()
	for i in range(40):
		combat._physics_process(0.016)
	_expect(combat.states[1].phase == combat.Phase.CLASH, "mutual dash starts clash")
	if "--preview" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png("/tmp/flowstate-arcade-clash.png")
	var fight: int = combat.states[1].fight
	combat.submit(1, combat.Action.E, 0, fight - 1)
	_expect(combat.states[1].phase == combat.Phase.CLASH, "stale inputs ignored")
	combat.submit(1, combat.Action.E, 0, fight)
	_expect(combat.states[1].phase == combat.Phase.SLAM, "wrong key loses")
	_expect(combat.states[2].phase == combat.Phase.OPEN, "winner can follow up")
	_reset()
	_dash_pair()
	combat._start_clash(1, 2)
	fight = combat.states[1].fight
	for i in range(6):
		combat.submit(1, i % 2, 0, fight)
	_expect(combat.states[2].phase == combat.Phase.SLAM, "six press lead wins")
	_reset()
	_dash_pair()
	combat._start_clash(1, 2)
	fight = combat.states[1].fight
	for i in range(4):
		combat.submit(1, i % 2, 0, fight)
		combat.submit(2, i % 2, 0, fight)
	for i in range(188):
		combat._physics_process(0.016)
	_expect(combat.states[1].phase == combat.Phase.CHOICE, "equal pace offers choice after three seconds")
	combat.submit(1, combat.Action.Q, 0, fight)
	combat.submit(2, combat.Action.E, 0, fight)
	_expect(combat.states[1].phase == combat.Phase.RETREAT, "q retreats")
	_expect(combat.states[2].phase == combat.Phase.VAULT, "e vaults")
	for i in range(30):
		combat._physics_process(0.016)
	_expect(combat.states[1].position.distance_to(Vector3(-5, 20, 0)) < 0.1, "retreat restores original position")
	_expect(combat.states[2].phase == combat.Phase.OPEN, "vault opens ground pound")
	combat.submit(1, combat.Action.Q, 2)
	_expect(combat.states[1].phase == combat.Phase.DASH, "q dashes again after retreat")
	_reset()
	first.position = Vector3(0, 20, 0)
	second.position = Vector3(0, 24, 0)
	first.stamina = 200
	combat.submit(2, combat.Action.POUND, 1)
	_expect(combat.states.has(2), "airborne attacker can pound")
	for i in range(20):
		combat._physics_process(0.016)
	_expect(first.stamina == 125, "pound costs victim exactly seventy five stamina once")
	_reset()
	second.team = first.team
	combat.submit(1, combat.Action.Q, 2)
	_expect(combat.states.is_empty(), "friendly targets rejected")
	second.team = 1
	first.position.y = 7.655
	combat.submit(1, combat.Action.Q, 2)
	_expect(combat.states.is_empty(), "underwater dash rejected")
	_reset()
	_dash_pair()
	Net.net_sync_game_mode(Net.GameMode.NORMAL)
	combat._physics_process(0.016)
	_expect(combat.states.is_empty() and combat._puppets.is_empty(), "mode change releases fighters")
	combat.submit(1, combat.Action.Q, 2)
	_expect(combat.states.is_empty(), "normal mode has no aerial combat")
	print("FAIL arcade combat" if failed else "PASS arcade combat")
	get_tree().quit(1 if failed else 0)


func _reset() -> void:
	for id in combat.states.keys():
		combat._release(id)
	combat._publish(true)
	combat._cooldowns.clear()
	first.position = Vector3(-5, 20, 0)
	second.position = Vector3(5, 20, 0)
	first.linear_velocity = Vector3.ZERO
	second.linear_velocity = Vector3.ZERO


func _dash_pair() -> void:
	combat.submit(1, combat.Action.Q, 2)
	combat.submit(2, combat.Action.Q, 1)
	_expect(combat.states.size() == 2, "both players can dash")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
