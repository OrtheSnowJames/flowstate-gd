extends Node

enum Move { NONE, POWER, ATTACK, WALL, PELT, COUNTER }
const MOVE_NAMES := ["None", "Water Power", "Water Attack", "Water Wall", "Water Pelt", "Water Counter"]

var move: Move = Move.NONE
var infinite_stamina := true
var display_name := ""
var _cooldown := 0.0
var _overlapping: Array[PhysicsBody3D] = []
@onready var player = get_parent()


func configure(chosen_move: int, infinite: bool, lifeguard: bool) -> void:
	player._cast_water_wall_stop()
	move = clampi(chosen_move, Move.NONE, Move.COUNTER) as Move
	infinite_stamina = infinite
	player.is_lifeguard = lifeguard
	_cooldown = 0.0
	if infinite_stamina:
		if player._unconscious:
			player.net_revive()
		player.stamina = player.max_stamina_per_mode(Net.game_mode)


func allow_spawn_overlap(other: PhysicsBody3D) -> void:
	get_parent().add_collision_exception_with(other)
	other.add_collision_exception_with(get_parent())
	_overlapping.append(other)


func _physics_process(delta: float) -> void:
	for index in range(_overlapping.size() - 1, -1, -1):
		var other = _overlapping[index]
		if not is_instance_valid(other):
			_overlapping.remove_at(index)
			continue
		var gap: Vector3 = other.global_position - player.global_position
		if Vector2(gap.x, gap.z).length() > 1.2 or absf(gap.y) > 2.1:
			player.remove_collision_exception_with(other)
			other.remove_collision_exception_with(player)
			_overlapping.remove_at(index)
	if Net.is_online():
		player.queue_free()
		return
	if Net.arcade.controls(player):
		return
	player._drift_to_a_stop()
	if player._unconscious:
		return
	if player.movement_locked or Net._round_over or Net.round_state != Net.RoundState.PLAYING or Net.input_blocked_by_menu():
		if player._water_wall_up:
			player._cast_water_wall_stop()
		return
	if infinite_stamina:
		player.stamina = player.max_stamina_per_mode(Net.game_mode)
	player.movement_state = player.MovementState.IDLE if player.in_shallow_end() else player.MovementState.TREAD
	player._update_water_counter(delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_cast(delta)
	if infinite_stamina:
		player.stamina = player.max_stamina_per_mode(Net.game_mode)
	else:
		player._stamina_change(delta)
		player.stamina = clampf(player.stamina, 0, player.max_stamina_per_mode(Net.game_mode))


func _cast(delta: float) -> void:
	if player._ocean == null or move == Move.NONE:
		return
	var aim: Vector3 = -player.global_basis.z.normalized()
	if move == Move.WALL:
		if player._submersion() > 0.0 and player.stamina > 5.0:
			var origin: Vector3 = player.global_position + aim * 1.2
			origin.y = player._water_height()
			player._cast_water_wall(origin, aim, 1.0)
			player.stamina -= player.water_wall_stamina_cost_per_second * delta
		elif player._water_wall_up:
			player._cast_water_wall_stop()
		return
	if _cooldown > 0.0 or player._water_wall_up:
		return
	if move != Move.PELT and player._submersion() <= 0.0:
		return
	var cost: float
	var interval: float
	var kind: int
	var origin: Vector3 = player.global_position + aim
	origin.y = player._water_height()
	match move:
		Move.POWER:
			kind = player.WaterMove.POWER
			cost = player.water_power_stamina_cost
			interval = player.water_power_cooldown
		Move.ATTACK:
			kind = player.WaterMove.ATTACK
			cost = player.water_attack_stamina_cost
			interval = player.water_attack_cooldown
			origin = player.global_position + aim * 0.6
			origin.y = player._water_height()
		Move.PELT:
			kind = player.WaterMove.PELT
			cost = player.water_pelt_stamina_cost
			interval = player.water_pelt_cooldown
			origin = player.global_position + Vector3.UP * 0.35
		Move.COUNTER:
			kind = player.WaterMove.COUNTER
			cost = player.water_counter_stamina_cost
			interval = maxf(1.0, player.water_power_cooldown)
	if player.stamina < cost:
		return
	player._cast_water_move(kind, origin, aim, 1.0)
	player.stamina -= cost
	_cooldown = interval


func _exit_tree() -> void:
	for other in _overlapping:
		if is_instance_valid(other):
			other.remove_collision_exception_with(get_parent())
