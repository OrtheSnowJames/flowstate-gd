extends Node

enum Phase { DASH, CLASH, CHOICE, RETREAT, VAULT, OPEN, SLAM, POUND }
enum Action { Q, E, POUND }

const DASH_SPEED := 32.0
const DASH_RANGE := 40.0
const CLASH_SECONDS := 3.0
const WIN_LEAD := 6
const TIE_MARGIN := 2
const POUND_DAMAGE := 75.0
const SNAPSHOT_INTERVAL := 0.05
const HUD := preload("res://water/arcade_hud.gd")
var ultimate = preload("res://water/arcade_ultimate.gd").new()

var states: Dictionary = {}
var view: Dictionary = {}
var _puppets: Dictionary = {}
var _cooldowns: Dictionary = {}
var _last_targets: Dictionary = {}
var _releases: Dictionary = {}
var _release_pending := false
var _clock := 0.0
var _snapshot_time := 0.0
var _version := 0
var _received_version := -1
var _fight_sequence := 0
var _hud: CanvasLayer


func _ready() -> void:
	ultimate.name = "Ultimate"
	ultimate.combat = self
	add_child(ultimate)
	_hud = HUD.new()
	_hud.controller = self
	add_child(_hud)


func active() -> bool:
	return Net.game_mode == Net.GameMode.ARCADE and Net.round_state == Net.RoundState.PLAYING and not Net._round_over


func _host() -> bool:
	return not Net.is_online() or multiplayer.is_server()


func _body(id: int) -> Node3D:
	if id < 0 and not Net.is_online() and is_instance_id_valid(-id):
		var bot = instance_from_id(-id)
		if bot is Node3D and bot.is_inside_tree() and bot.is_in_group("player") and bot.practice != null:
			return bot
	var players := Net._players_root()
	return players.get_node_or_null(str(id)) as Node3D if players else null


func _id(player) -> int:
	# negative ids keep solo bots separate from network peers
	return -player.get_instance_id() if player.practice != null else player._owner_peer


func _combatants() -> Array[Node]:
	var players: Array[Node] = []
	for player in get_tree().get_nodes_in_group("player"):
		if not player.is_queued_for_deletion() and (player.practice == null or not Net.is_online()):
			players.append(player)
	return players


func _position(id: int) -> Vector3:
	if states.has(id):
		return states[id].position
	var player := _body(id)
	return player.global_position if player else Vector3.ZERO


func _available(id: int) -> bool:
	var player := _body(id)
	return player != null and not player.is_queued_for_deletion() and not player._unconscious and not player.movement_locked \
		and player.movement_state != player.MovementState.HURDLE


func _enemies(a: int, b: int) -> bool:
	return a != b and _available(a) and _available(b) and _body(a).team != _body(b).team


func airborne(player) -> bool:
	if player.global_position.y <= player._water_height() + player.body_half_height * 0.75:
		return false
	var query := PhysicsRayQueryParameters3D.create(player.global_position,
		player.global_position + Vector3.DOWN * (player.body_half_height + 0.15), 1, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func controls(player) -> bool:
	return active() and (_puppets.has(_id(player)) or ultimate.holding(player))


func pick_target(player) -> int:
	if not active() or not is_instance_valid(player._camera):
		return 0
	var camera: Camera3D = VR.view_camera(player._camera)
	var mouse: Vector2 = player.Controller.aim_position(player)
	var controller_aim: bool = VR.active or player.using_controller
	var best := 1.0 - cos(deg_to_rad(25.0)) if controller_aim else 160.0
	var target := 0
	var id := _id(player)
	for other in _combatants():
		var other_id := _id(other)
		if not _enemies(id, other_id) or camera.is_position_behind(other.global_position):
			continue
		if player.global_position.distance_to(other.global_position) > DASH_RANGE:
			continue
		var distance := VR.project_ui_position(other.global_position, camera).distance_to(mouse)
		if controller_aim:
			var direction := camera.global_position.direction_to(other.global_position)
			distance = 1.0 - (-camera.global_basis.z).dot(direction)
		if distance < best and _clear_path(player.global_position, other.global_position):
			best = distance
			target = other_id
	return target


func pick_pound_target(player) -> int:
	if not active():
		return 0
	var id := _id(player)
	var target := 0
	var best := INF
	for other in _combatants():
		var other_id := _id(other)
		if not _can_pound_target(id, other_id):
			continue
		var offset := _position(other_id) - _position(id)
		var distance := Vector2(offset.x, offset.z).length_squared()
		if distance < best:
			best = distance
			target = other_id
	return target


func _can_pound_target(id: int, target: int) -> bool:
	if not _enemies(id, target):
		return false
	var offset := _position(target) - _position(id)
	return offset.y <= -0.5 and Vector2(offset.x, offset.z).length() <= 12.0 \
		and _clear_path(_position(id), _position(target))


func handle_input(player, event: InputEvent) -> bool:
	if not active() or not player._is_local():
		return false
	if event.is_echo():
		return controls(player)
	if ultimate.handle_input(player, event):
		return true
	var id := _id(player)
	if event.is_action_pressed("arcade_q"):
		request_action(Action.Q, pick_target(player), int(view.get(id, {}).get("fight", 0)))
		return true
	if event.is_action_pressed("arcade_e"):
		request_action(Action.E, 0, int(view.get(id, {}).get("fight", 0)))
		return true
	if (event.is_action_pressed("jump") and Input.is_action_pressed("swim_key")) \
			or (event.is_action_pressed("swim_key") and Input.is_action_pressed("jump")):
		request_action(Action.POUND, pick_pound_target(player), int(view.get(id, {}).get("fight", 0)))
		return true
	return controls(player)


func request_action(action: int, target: int, fight: int) -> void:
	if _host():
		submit(1, action, target, fight)
	else:
		rpc_id(1, "net_action", action, target, fight)


@rpc("any_peer", "reliable")
func net_action(action: int, target: int, fight: int) -> void:
	if _host():
		submit(multiplayer.get_remote_sender_id(), action, target, fight)


func submit(id: int, action: int, target: int = 0, fight: int = 0) -> void:
	if not _host() or not active() or not _available(id):
		return
	if ultimate.held.has(id):
		return
	var state: Dictionary = states.get(id, {})
	if not state.is_empty() and state.phase == Phase.CLASH:
		if fight != state.fight or action not in [Action.Q, Action.E]:
			return
		if action != state.next:
			_lose(id)
		else:
			state.score += 1
			state.next = Action.E if action == Action.Q else Action.Q
			var rival: Dictionary = states.get(state.target, {})
			if not rival.is_empty() and state.score - rival.score >= WIN_LEAD:
				_lose(state.target)
		_publish(true)
		return
	if not state.is_empty() and state.phase == Phase.CHOICE:
		if fight != state.fight:
			return
		if action == Action.Q:
			_set_phase(state, Phase.RETREAT, 1.5)
		elif action == Action.E and _available(state.target):
			state.destination = _position(state.target) + Vector3.UP * 3.5
			state.start = state.position
			_set_phase(state, Phase.VAULT, 0.4)
		_publish(true)
		return
	if not state.is_empty() and state.phase != Phase.OPEN:
		return
	if action == Action.Q:
		if target == 0 and not state.is_empty():
			target = state.target
		_start_dash(id, target)
	elif action == Action.POUND:
		_start_pound(id, target)


func _state(id: int, target: int, phase: Phase, duration: float) -> Dictionary:
	return {"phase": phase, "target": target, "position": _position(id),
		"origin": _position(id), "velocity": Vector3.ZERO, "time": duration,
		"score": 0, "next": Action.Q, "fight": 0}


func _start_dash(id: int, target: int) -> void:
	if not _enemies(id, target) or _clock < float(_cooldowns.get(id, 0.0)):
		return
	var player := _body(id)
	if player._water_wall_up or not airborne(player):
		return
	if _position(id).distance_to(_position(target)) > DASH_RANGE or not _clear_path(_position(id), _position(target)):
		return
	states[id] = _state(id, target, Phase.DASH, 1.5)
	_last_targets[id] = target
	_cooldowns[id] = _clock + 0.65
	_releases.erase(id)
	_publish(true)


func _start_pound(id: int, target: int) -> void:
	var state: Dictionary = states.get(id, {})
	if not state.is_empty():
		target = state.target
	elif target == 0:
		target = int(_last_targets.get(id, 0))
	if not _can_pound_target(id, target) or _body(id)._water_wall_up or not airborne(_body(id)):
		return
	states[id] = _state(id, target, Phase.POUND, 1.5)
	_releases.erase(id)
	_publish(true)


func _set_phase(state: Dictionary, phase: Phase, duration: float) -> void:
	state.phase = phase
	state.time = duration
	state.velocity = Vector3.ZERO


func _start_clash(a: int, b: int) -> void:
	_fight_sequence += 1
	var midpoint := (_position(a) + _position(b)) * 0.5
	var axis := _position(a) - _position(b)
	axis.y = 0.0
	axis = axis.normalized() if axis.length_squared() > 0.01 else Vector3.RIGHT
	for id in [a, b]:
		var state: Dictionary = states[id]
		state.position = midpoint + axis * (0.65 if id == a else -0.65)
		state.score = 0
		state.next = Action.Q
		state.fight = _fight_sequence
		_set_phase(state, Phase.CLASH, CLASH_SECONDS)
	_publish(true)


func _lose(loser: int) -> void:
	if not states.has(loser):
		return
	var state: Dictionary = states[loser]
	var winner: int = state.target
	_set_phase(state, Phase.SLAM, 1.5)
	state.velocity = Vector3.DOWN * 35.0
	if states.has(winner):
		_set_phase(states[winner], Phase.OPEN, 1.5)


func _finish_clash(a: int) -> void:
	var first: Dictionary = states[a]
	var b: int = first.target
	if not states.has(b):
		_release(a)
		return
	var second: Dictionary = states[b]
	if abs(int(first.score) - int(second.score)) > TIE_MARGIN:
		_lose(a if first.score < second.score else b)
	else:
		for state in [first, second]:
			_set_phase(state, Phase.CHOICE, 2.5)
	_publish(true)


func _release(id: int) -> void:
	if states.has(id):
		_releases[id] = {"position": states[id].position, "velocity": states[id].velocity}
		states.erase(id)
		_release_pending = true


func _physics_process(delta: float) -> void:
	_clock += delta
	if not active():
		if not states.is_empty() and _host():
			states.clear()
			_publish(true)
		view.clear()
		for id in _puppets.keys():
			_restore(id, {})
		_received_version = -1
		_cooldowns.clear()
		_last_targets.clear()
		_releases.clear()
		_release_pending = false
		return
	if not _host():
		return
	for id in states.keys():
		if not states.has(id):
			continue
		var state: Dictionary = states[id]
		if not _enemies(id, state.target):
			_release(id)
			continue
		state.time -= delta
		match state.phase:
			Phase.CLASH:
				if state.time <= 0.0:
					_finish_clash(id)
			Phase.CHOICE:
				if state.time <= 0.0:
					_set_phase(state, Phase.RETREAT, 1.5)
			Phase.OPEN:
				if state.time <= 0.0:
					_release(id)
			_:
				_move(id, state, delta)
	_snapshot_time += delta
	if _snapshot_time >= SNAPSHOT_INTERVAL:
		_snapshot_time = 0.0
		_publish(false)


func _move(id: int, state: Dictionary, delta: float) -> void:
	var start: Vector3 = state.position
	var target := _position(state.target)
	var next := start
	match state.phase:
		Phase.DASH:
			state.velocity = (target - start).normalized() * DASH_SPEED
			next = start.move_toward(target, DASH_SPEED * delta)
			if Geometry3D.get_closest_point_to_segment(target, start, next).distance_to(target) <= 1.3:
				var rival: Dictionary = states.get(state.target, {})
				if rival.get("phase", -1) == Phase.DASH and rival.target == id:
					_start_clash(id, state.target)
					return
				_set_phase(state, Phase.OPEN, 0.5)
				return
		Phase.RETREAT:
			state.velocity = (state.origin - start).normalized() * DASH_SPEED
			next = start.move_toward(state.origin, DASH_SPEED * delta)
			if next.distance_to(state.origin) < 0.05:
				_set_phase(state, Phase.OPEN, 1.5)
				_cooldowns[id] = 0.0
		Phase.VAULT:
			var progress := clampf(1.0 - state.time / 0.4, 0.0, 1.0)
			next = state.start.lerp(state.destination, progress) + Vector3.UP * sin(progress * PI)
			state.velocity = (next - start) / delta
			if progress >= 1.0:
				_set_phase(state, Phase.OPEN, 1.2)
		Phase.SLAM:
			next = start + state.velocity * delta
		Phase.POUND:
			var horizontal := Vector3(target.x - start.x, 0.0, target.z - start.z)
			state.velocity = horizontal.limit_length(1.0) * 20.0 + Vector3.DOWN * 48.0
			next = start + state.velocity * delta
			next = _safe_motion(start, next)
			var closest := Geometry3D.get_closest_point_to_segment(target, start, next)
			if closest.distance_to(target) <= 1.3 and start.y >= target.y:
				state.position = next
				_release(id)
				_release(state.target)
				_publish(true)
				if Net.is_online():
					rpc("net_pound_hit", state.target, id)
				else:
					net_pound_hit(state.target, id)
				return
	var motion := _safe_motion(start, next)
	state.position = motion
	if motion.distance_to(next) > 0.05 or state.time <= 0.0:
		state.velocity = Vector3.ZERO
		_release(id)


func _excluded_players() -> Array[RID]:
	var excluded: Array[RID] = []
	for player in get_tree().get_nodes_in_group("player"):
		if player is CollisionObject3D:
			excluded.append(player.get_rid())
	return excluded


func _clear_path(start: Vector3, end: Vector3) -> bool:
	var player := _body(1)
	if player == null:
		var players := Net._players_root()
		if players == null or players.get_child_count() == 0:
			return false
		player = players.get_child(0)
	var query := PhysicsRayQueryParameters3D.create(start, end, 1, _excluded_players())
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _safe_motion(start: Vector3, end: Vector3) -> Vector3:
	var players := Net._players_root()
	if players == null or players.get_child_count() == 0:
		return start
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.9
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = start
	query.motion = end - start
	query.collision_mask = 1
	query.exclude = _excluded_players()
	var motion: PackedFloat32Array = players.get_child(0).get_world_3d().direct_space_state.cast_motion(query)
	return start.lerp(end, motion[0]) if motion.size() == 2 else start


@rpc("authority", "call_local", "reliable")
func net_pound_hit(id: int, attacker: int = 0) -> void:
	var player := _body(id)
	if player == null or player._unconscious:
		return
	if player._is_local():
		if player.practice == null or not player.practice.infinite_stamina:
			player._last_damage_peer = attacker
			player._last_damage_time = Time.get_ticks_msec()
			player.stamina = maxf(0.0, player.stamina - POUND_DAMAGE)
		player.linear_velocity = Vector3.DOWN * 30.0
		player.shake_camera(0.25, 0.35)
		if player.stamina <= 5.0:
			player._death()
	if player._ocean:
		player._ocean._spawn_splash(player.global_position, 600.0, 1.8)


func _publish(reliable: bool) -> void:
	reliable = reliable or _release_pending
	_release_pending = false
	_version += 1
	var snapshot := states.duplicate(true)
	if Net.is_online():
		rpc("net_event" if reliable else "net_snapshot", _version, snapshot, _releases)
	else:
		_receive(_version, snapshot, _releases)


@rpc("authority", "call_local", "unreliable_ordered", 1)
func net_snapshot(version: int, snapshot: Dictionary, releases: Dictionary) -> void:
	_receive(version, snapshot, releases)


@rpc("authority", "call_local", "reliable")
func net_event(version: int, snapshot: Dictionary, releases: Dictionary) -> void:
	_receive(version, snapshot, releases)


func _receive(version: int, snapshot: Dictionary, releases: Dictionary) -> void:
	if not active() or version <= _received_version:
		return
	_received_version = version
	view = snapshot
	for id in _puppets.keys():
		if not snapshot.has(id):
			_restore(id, releases.get(id, {}))
	for id in snapshot:
		var player := _body(id)
		if player == null or player._unconscious:
			continue
		var state: Dictionary = snapshot[id]
		if not _puppets.has(id):
			player._jump_spent = true
			_puppets[id] = {"body": player, "freeze": player.freeze, "phase": -1}
			player.freeze = true
			player.net_water_wall_stop()
		var puppet: Dictionary = _puppets[id]
		puppet.from = player.global_position
		puppet.to = state.position
		puppet.age = 0.0
		if puppet.phase != state.phase:
			puppet.phase = state.phase
			var clip := "water_attack" if state.phase == Phase.CLASH else "jump_high"
			if player._anim_player == null:
				continue
			if not player._anim_player.has_animation(clip):
				clip = "jump"
			player._play_water_action_anim(clip)


func _restore(id: int, release: Dictionary) -> void:
	var puppet: Dictionary = _puppets[id]
	var player = puppet.body
	if is_instance_valid(player):
		player.global_position = release.get("position", player.global_position)
		player.freeze = puppet.freeze
		player.linear_velocity = release.get("velocity", Vector3.ZERO)
		player._remote_from = player.transform
		player._remote_transform = player.transform
		player._action_anim_lock_movement_state = -1
		player.reset_physics_interpolation()
	_puppets.erase(id)


func _process(delta: float) -> void:
	for id in _puppets.keys():
		var puppet: Dictionary = _puppets[id]
		var player = puppet.body
		if not is_instance_valid(player):
			_puppets.erase(id)
			continue
		puppet.age += delta
		player.global_position = puppet.from.lerp(puppet.to, minf(puppet.age / SNAPSHOT_INTERVAL, 1.0))
		player.linear_velocity = Vector3.ZERO
