extends Node3D

const BALLOON_COUNT := 5
const PICKUP_RANGE := 3.0
const RESPAWN_SECONDS := 5.0
const COLORS := [Color("ffc43d"), Color("f23846"), Color("2689ff"), Color("ad45e8")]

var items: Dictionary = {}
var control := Net.CubeControl.NEUTRAL
var _enabled := false
var _down_seconds: Dictionary = {}
var _awaiting_death: Dictionary = {}
var _throw_times: Dictionary = {}
var _pickups: Dictionary = {}
var _material := StandardMaterial3D.new()
var _prompt: Control

@onready var tub: Node3D = get_parent().get_node("hot tub/Hottubsquare")
@onready var bucket: Node3D = $Bucket


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	$TubMarker.material_override = _material
	Net.game_mode_changed.connect(_mode_changed)
	_mode_changed()
	if Net.is_online() and not multiplayer.is_server():
		Net.net_sync_pool_party(Net._pool_party_state)
		Net.rpc_id(1, "net_request_pool_party")


func authoritative() -> bool:
	return not Net.is_online() or multiplayer.is_server()


func active() -> bool:
	return _enabled and Net.round_state == Net.RoundState.PLAYING and Net._round_started and not Net._round_over


func _mode_changed() -> void:
	var enabled: bool = Net.game_mode == Net.GameMode.POOL_PARTY and not get_parent().delete_players
	visible = enabled
	for body in $Inflatables.get_children() + [$TubFloor]:
		body.collision_layer = 1 if enabled else 0
		body.collision_mask = 1 if enabled else 0
	if enabled == _enabled:
		return
	_enabled = enabled
	items.clear()
	_down_seconds.clear()
	_awaiting_death.clear()
	_throw_times.clear()
	control = Net.CubeControl.NEUTRAL
	if enabled and authoritative():
		for id in range(1, BALLOON_COUNT + 1):
			items[id] = {"state": "ground", "owner": 0, "position": Vector3(-17, 8.0, (id - 3) * 4.0), "projectile": 0}
		publish()
	else:
		_refresh_visuals()


func player_id(player: Node3D) -> int:
	return player._owner_peer if player._owner_peer > 0 else -player.get_instance_id()


func in_tub(player: Node3D) -> bool:
	var point := tub.to_local(player.global_position)
	return absf(point.x) < 2.45 and absf(point.z) < 3.35 and point.y >= 0.0 and point.y <= 3.1


func on_inflatable(player: Node3D) -> bool:
	var support: Dictionary = player.Movement._jump_surface(player)
	return support.get("collider") in $Inflatables.get_children()


func capacity(player: Node3D) -> int:
	return 1 if in_tub(player) else 4


func carried(player: Node3D) -> Array:
	var result := []
	var owner := player_id(player)
	for id in items:
		if items[id].state == "held" and items[id].owner == owner:
			result.append(id)
	return result


func bucket_count() -> int:
	var count := 0
	for item in items.values():
		if item.state == "bucket":
			count += 1
	return count


func pickup_target(player: Node3D) -> int:
	if not active() or player._unconscious or player.movement_locked or carried(player).size() >= capacity(player):
		return 0
	var nearest := PICKUP_RANGE
	var target := 0
	for id in items:
		if items[id].state not in ["ground", "bucket"]:
			continue
		var position: Vector3 = bucket.global_position if items[id].state == "bucket" else items[id].position
		var distance := player.global_position.distance_to(position)
		if distance > nearest:
			continue
		var query := PhysicsRayQueryParameters3D.create(player.global_position, position, 1, [player.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		nearest = distance
		target = id
	return target


func pickup(player: Node3D) -> void:
	if not authoritative():
		return
	var id := pickup_target(player)
	if id == 0:
		return
	items[id].state = "held"
	items[id].owner = player_id(player)
	publish()


func take_for_throw(player: Node3D, projectile: int) -> bool:
	if not authoritative() or not active():
		return false
	var stored := _store_excess(player)
	var held := carried(player)
	var owner := player_id(player)
	var now := Time.get_ticks_msec() * 0.001
	if held.is_empty() or now - float(_throw_times.get(owner, -100.0)) < player.water_pelt_cooldown:
		if stored:
			publish()
		return false
	_throw_times[owner] = now
	items[held[0]].state = "flight"
	items[held[0]].position = player.global_position
	items[held[0]].projectile = projectile
	publish()
	return true


func land(body: RigidBody3D, victim: Node3D) -> int:
	var score_team := -1
	var thrower := Net._water_balloon_player(body.thrower_id)
	for item in items.values():
		if item.state != "flight" or item.projectile != body.balloon_id:
			continue
		_drop(item, body.global_position)
		if is_instance_valid(thrower) and is_instance_valid(victim) and not victim._unconscious \
				and victim.team != thrower.team and not _down_seconds.has(player_id(victim)) and active():
			control = occupancy()
			var team_control := Net.CubeControl.RED if thrower.team == Net.PLAYER_SCRIPT.Team.RED else Net.CubeControl.BLUE
			if control == team_control and not thrower._unconscious and (in_tub(thrower) or on_inflatable(thrower)):
				score_team = thrower.team
			_down_seconds[player_id(victim)] = 0.0
			_awaiting_death[player_id(victim)] = true
			_drop_carried(victim)
		break
	publish()
	return score_team


func occupancy() -> int:
	var red := false
	var blue := false
	for player in get_tree().get_nodes_in_group("player"):
		if player.is_queued_for_deletion() or player._unconscious or player.movement_locked or not in_tub(player):
			continue
		red = red or player.team == Net.PLAYER_SCRIPT.Team.RED
		blue = blue or player.team == Net.PLAYER_SCRIPT.Team.BLUE
	if red and blue:
		return Net.CubeControl.CONTESTED
	if red:
		return Net.CubeControl.RED
	return Net.CubeControl.BLUE if blue else Net.CubeControl.NEUTRAL


func _physics_process(delta: float) -> void:
	if not authoritative() or not active():
		return
	for id in _down_seconds.keys():
		if not is_instance_valid(Net._water_balloon_player(id)):
			_down_seconds.erase(id)
			_awaiting_death.erase(id)
	var changed := false
	var next := occupancy()
	if control != next:
		control = next
		changed = true
	for player in get_tree().get_nodes_in_group("player"):
		var id := player_id(player)
		if player._unconscious:
			changed = _drop_carried(player) or changed
			_awaiting_death.erase(id)
			_down_seconds[id] = float(_down_seconds.get(id, 0.0)) + delta
			if _down_seconds[id] >= RESPAWN_SECONDS:
				if Net.is_online():
					Net.rpc("net_party_respawn", id)
				else:
					Net.net_party_respawn(id)
				_down_seconds.erase(id)
		elif _awaiting_death.has(id):
			# wait for the owners death message before another hit can score
			continue
		else:
			_down_seconds.erase(id)
			changed = _store_excess(player) or changed
	for item in items.values():
		if item.state == "held":
			var player := Net._water_balloon_player(item.owner)
			if is_instance_valid(player) and not player.is_queued_for_deletion():
				item.position = player.global_position
			else:
				_drop(item, item.position)
				changed = true
		elif item.state == "flight":
			var balloon = Net._water_balloons.get(item.projectile)
			if is_instance_valid(balloon) and not balloon.is_queued_for_deletion():
				item.position = balloon.get_node("RigidBody3D").global_position
			else:
				_drop(item, item.position)
				changed = true
	if changed:
		publish()


func _store_excess(player: Node3D) -> bool:
	var held := carried(player)
	if held.size() <= capacity(player):
		return false
	for id in held.slice(capacity(player)):
		items[id].state = "bucket"
		items[id].owner = 0
		items[id].position = bucket.global_position
	return true


func _drop_carried(player: Node3D) -> bool:
	var held := carried(player)
	for i in held.size():
		_drop(items[held[i]], player.global_position + Vector3(cos(i * TAU / held.size()), 0, sin(i * TAU / held.size())) * 0.7)
	return not held.is_empty()


func _drop(item: Dictionary, at: Vector3) -> void:
	# keep missed balloons inside the playable pool and above the water
	at.x = clampf(at.x, -25.0, 32.5)
	at.z = clampf(at.z, -20.0, 20.0)
	var excluded: Array[RID] = []
	for player in get_tree().get_nodes_in_group("player"):
		excluded.append(player.get_rid())
	for balloon in Net._water_balloons.values():
		if is_instance_valid(balloon):
			excluded.append(balloon.get_node("RigidBody3D").get_rid())
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, Vector3(at.x, -20, at.z), 1, excluded)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	at.y = maxf(8.0, float(hit.position.y) + 0.4 if not hit.is_empty() else 8.0)
	item.state = "ground"
	item.owner = 0
	item.projectile = 0
	item.position = at


func publish() -> void:
	_refresh_visuals()
	Net.net_sync_pool_party({"items": items.duplicate(true), "control": control})
	if Net.is_online():
		for peer in Net._arena_ready:
			if peer != 1:
				Net.rpc_id(peer, "net_sync_pool_party", Net._pool_party_state)


func apply_state(state: Dictionary) -> void:
	if not _enabled or state.is_empty():
		return
	items = state.get("items", {}).duplicate(true)
	control = int(state.get("control", Net.CubeControl.NEUTRAL))
	_refresh_visuals()


func _refresh_visuals() -> void:
	_material.albedo_color = COLORS[control]
	$TubMarker/Label.text = ["Hot tub: unclaimed", "Hot tub: red", "Hot tub: blue", "Hot tub: contested"][control]
	$Bucket/Label.text = "Balloons: %d" % bucket_count()
	for id in _pickups.keys():
		if not items.has(id) or items[id].state != "ground":
			_pickups[id].queue_free()
			_pickups.erase(id)
	for id in items:
		if items[id].state != "ground":
			continue
		if not _pickups.has(id):
			var pickup := preload("res://water/balloon_pickup.tscn").instantiate()
			pickup.name = "Balloon_%d" % id
			$Pickups.add_child(pickup)
			_pickups[id] = pickup
		_pickups[id].global_position = items[id].position


func _process(_delta: float) -> void:
	if not _enabled or is_instance_valid(_prompt):
		return
	for player in get_tree().get_nodes_in_group("player"):
		if player._is_local() and player.practice == null and is_instance_valid(player.gui):
			_prompt = preload("res://prompts/balloon_pickup_prompt.tscn").instantiate()
			_prompt.player = player
			player.gui.add_child(_prompt)
			return
