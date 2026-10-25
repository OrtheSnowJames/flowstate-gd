extends Node

const KILLS_REQUIRED := 3
const HOLD_TIME := 0.35
const SPEED := 32.0
const LIFETIME := 4.0
const HEIGHT := Vector3(0, 3, 0)

var combat: Node
var charges: Dictionary = {}
var held: Dictionary = {}
var shots: Dictionary = {}
var _credited: Dictionary = {}
var _poses: Dictionary = {}
var _visuals: Dictionary = {}
var _sequence := 0
var _hold_time := 0.0
var _pending_q := -1.0
var _requested := false
var _throw_armed := false
var _shape := BoxShape3D.new()
var _jump_pose: Animation


func _ready() -> void:
	_shape.size = Vector3.ONE * 1.6


func credit(victim, killer: int) -> void:
	if not combat._host() or not combat.active() or killer <= 0:
		return
	var attacker = combat._body(killer)
	var key: int = victim.get_instance_id()
	if attacker == null or attacker == victim or attacker.team == victim.team or _credited.has(key):
		return
	_credited[key] = true
	charges[killer] = mini(KILLS_REQUIRED, int(charges.get(killer, 0)) + 1)
	_publish()


func reset_life(player) -> void:
	_credited.erase(player.get_instance_id())


func holding(player) -> bool:
	return player._owner_peer > 0 and held.has(player._owner_peer)


func handle_input(player, event: InputEvent) -> bool:
	if holding(player):
		var click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		var trigger := event.is_action_pressed("arcade_q") and not event is InputEventKey and _throw_armed
		if click or trigger:
			var direction: Vector3 = player._mouse_aim_direction_3d(player.global_position + HEIGHT)
			if combat._host():
				throw_cube(str(player.name).to_int(), direction)
			else:
				rpc_id(1, "net_throw", direction)
		return true
	var id := str(player.name).to_int()
	if charges.get(id, 0) < KILLS_REQUIRED or combat.view.has(id):
		return false
	if event.is_action_pressed("arcade_q"):
		_pending_q = 0.0
		return true
	return event.is_action_pressed("arcade_e")


func _poll_input(delta: float) -> void:
	var id := multiplayer.get_unique_id() if Net.is_online() else 1
	var player = combat._body(id)
	if player == null or not combat._available(id) or Net.input_blocked_by_menu() or Net.is_spectating():
		_hold_time = 0.0
		_pending_q = -1.0
		return
	var q := Input.is_action_pressed("arcade_q")
	var e := Input.is_action_pressed("arcade_e")
	if not q:
		_throw_armed = true
	if holding(player):
		_pending_q = -1.0
		return
	if not q or not e:
		_hold_time = 0.0
		_requested = false
	if charges.get(id, 0) >= KILLS_REQUIRED and not combat.view.has(id) and q and e:
		_pending_q = -1.0
		_hold_time += delta
		if _hold_time >= HOLD_TIME and not _requested:
			_requested = true
			_throw_armed = false
			if combat._host():
				activate(id)
			else:
				rpc_id(1, "net_activate")
	elif _pending_q >= 0.0:
		_pending_q += delta
		if _pending_q >= 0.2 or not q:
			_pending_q = -1.0
			combat.request_action(combat.Action.Q, combat.pick_target(player), 0)


@rpc("any_peer", "reliable")
func net_activate() -> void:
	activate(multiplayer.get_remote_sender_id())


func activate(id: int) -> void:
	if not combat._host() or not combat.active() or not combat._available(id):
		return
	if charges.get(id, 0) < KILLS_REQUIRED or held.has(id) or combat.states.has(id):
		return
	charges[id] = 0
	held[id] = true
	combat._body(id).net_water_wall_stop()
	_publish()


@rpc("any_peer", "reliable")
func net_throw(direction: Vector3) -> void:
	throw_cube(multiplayer.get_remote_sender_id(), direction)


func throw_cube(id: int, direction: Vector3) -> void:
	if not combat._host() or not combat.active() or not held.has(id) or not combat._available(id):
		return
	if not direction.is_finite() or direction.is_zero_approx():
		return
	_sequence += 1
	shots[_sequence] = {"owner": id, "position": combat._body(id).global_position + HEIGHT,
		"direction": direction.normalized(), "life": LIFETIME, "hits": {}}
	held.erase(id)
	_publish()


func _publish() -> void:
	if Net.is_online():
		rpc("net_sync", charges, held, shots)
	else:
		_sync_visuals()


func sync_peer(id: int) -> void:
	if combat._host():
		rpc_id(id, "net_sync", charges, held, shots)


@rpc("authority", "call_local", "reliable")
func net_sync(new_charges: Dictionary, new_held: Dictionary, new_shots: Dictionary) -> void:
	if not combat._host():
		charges = new_charges.duplicate(true)
		held = new_held.duplicate(true)
		shots = new_shots.duplicate(true)
	_sync_visuals()


func _make_cube(key: String) -> void:
	if _visuals.has(key):
		return
	var scene := get_tree().current_scene
	var source := scene.get_node_or_null("PushCube/MeshInstance3D") as MeshInstance3D if scene else null
	if source == null:
		return
	var cube := MeshInstance3D.new()
	cube.name = "Ultimate_" + key
	cube.mesh = source.mesh
	cube.material_override = source.material_override
	cube.scale = source.global_basis.get_scale()
	add_child(cube)
	_visuals[key] = cube
	_shape.size = source.get_aabb().size * cube.scale


func _sync_visuals() -> void:
	for id in _poses.keys():
		if not held.has(id):
			_release_pose(id)
	for key in _visuals.keys():
		var id := str(key).substr(1).to_int()
		if (str(key).begins_with("h") and not held.has(id)) or (str(key).begins_with("s") and not shots.has(id)):
			_visuals[key].queue_free()
			_visuals.erase(key)
	for id in held:
		var player = combat._body(id)
		if player == null:
			continue
		_make_cube("h%d" % id)
		if _poses.has(id):
			continue
		if player._is_local():
			_throw_armed = not Input.is_action_pressed("arcade_q")
		_poses[id] = {"body": player, "freeze": player.freeze}
		player.freeze = true
		player.linear_velocity = Vector3.ZERO
		player.net_water_wall_stop()
		var anim: AnimationPlayer = player._anim_player
		if anim:
			_add_jump_pose(player)
			player._play_water_action_anim("jump_high")
			anim.seek(anim.get_animation("jump_high").length, true)
			anim.pause()
	for id in shots:
		_make_cube("s%d" % id)
	_update_visuals()


func _add_jump_pose(player) -> void:
	var anim: AnimationPlayer = player._anim_player
	if anim.has_animation("jump_high"):
		return
	# the lifeguard shares the rig but has no jump clip
	if _jump_pose == null:
		var source: Node = player._CHARACTER_MESH.instantiate()
		_jump_pose = source.get_node("AnimationPlayer").get_animation("jump_high").duplicate()
		source.free()
	var library := AnimationLibrary.new()
	if anim.has_animation_library(""):
		library = anim.get_animation_library("").duplicate()
		anim.remove_animation_library("")
	library.add_animation("jump_high", _jump_pose)
	anim.add_animation_library("", library)


func _release_pose(id: int) -> void:
	var pose: Dictionary = _poses[id]
	var player = pose.body
	if is_instance_valid(player):
		player.freeze = pose.freeze
		player._action_anim_lock_movement_state = -1
		player._movement_anim_state = -1
	_poses.erase(id)


func _update_visuals() -> void:
	for id in held:
		var player = combat._body(id)
		var cube = _visuals.get("h%d" % id)
		if player and is_instance_valid(cube):
			cube.global_position = player.global_position + HEIGHT
	for id in shots:
		var cube = _visuals.get("s%d" % id)
		if is_instance_valid(cube):
			cube.global_position = shots[id].position


func _physics_process(delta: float) -> void:
	if not combat.active():
		if not charges.is_empty() or not held.is_empty() or not shots.is_empty() or not _credited.is_empty():
			charges.clear()
			held.clear()
			shots.clear()
			_credited.clear()
			_sync_visuals()
		_hold_time = 0.0
		_pending_q = -1.0
		_requested = false
		return
	_poll_input(delta)
	if held.size() != _poses.size():
		_sync_visuals()
	var changed := false
	if combat._host():
		for id in charges.keys():
			if combat._body(id) == null:
				charges.erase(id)
				changed = true
		for id in held.keys():
			if not combat._available(id):
				held.erase(id)
				changed = true
	for id in shots.keys():
		var shot: Dictionary = shots[id]
		var start: Vector3 = shot.position
		var motion: Vector3 = shot.direction * SPEED * delta
		if combat._host():
			_hit_players(shot, start, motion)
		shot.position += motion
		shot.life -= delta
		if shot.life <= 0.0:
			shots.erase(id)
			changed = true
	if changed:
		if combat._host():
			_publish()
		else:
			_sync_visuals()
	_update_visuals()


func _hit_players(shot: Dictionary, start: Vector3, motion: Vector3) -> void:
	var players := get_tree().get_nodes_in_group("player")
	for player in players:
		if player == combat._body(shot.owner) or player._unconscious or player.is_queued_for_deletion():
			continue
		var path: NodePath = player.get_path()
		if shot.hits.has(path):
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _shape
		query.transform.origin = start
		query.motion = motion
		query.collision_mask = 1 << 19
		var excluded: Array[RID] = []
		for other in players:
			if other != player:
				excluded.append(other.get_rid())
		query.exclude = excluded
		var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		var sweep := space.cast_motion(query)
		if space.intersect_shape(query, 1).is_empty() and (sweep.size() != 2 or sweep[0] >= 1.0):
			continue
		shot.hits[path] = true
		if Net.is_online():
			rpc("net_hit", path, shot.owner)
		else:
			net_hit(path, shot.owner)


@rpc("authority", "call_local", "reliable")
func net_hit(path: NodePath, killer: int) -> void:
	var player = get_node_or_null(path)
	if player == null or not player.is_in_group("player") or player._unconscious:
		return
	player.stamina = 0.0
	player.net_death(killer)
