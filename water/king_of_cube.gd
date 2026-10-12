extends Node

const COLORS := [Color("ffc43d"), Color("f23846"), Color("2689ff"), Color("ad45e8")]
const RESPAWN_SECONDS := 5.0

@onready var _cube: RigidBody3D = get_parent()
@onready var _mesh: MeshInstance3D = _cube.get_node("MeshInstance3D")
var _original: Material
var _material := StandardMaterial3D.new()
var _held_seconds := 0.0
var _down_seconds: Dictionary = {}


func _ready() -> void:
	_original = _mesh.material_override
	_material.roughness = 0.35
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 0.35
	Net.cube_control_changed.connect(_update_color)
	_update_color()


func _update_color() -> void:
	if Net.game_mode != Net.GameMode.KING_OF_CUBE:
		_mesh.material_override = _original
		return
	_material.albedo_color = COLORS[Net.cube_control]
	_material.emission = _material.albedo_color
	_material.metallic = 0.55 if Net.cube_control == Net.CubeControl.NEUTRAL else 0.1
	_mesh.material_override = _material


func _physics_process(delta: float) -> void:
	if Net.is_online() and not multiplayer.is_server():
		return
	if not Net.cube_round_active():
		_held_seconds = 0.0
		_down_seconds.clear()
		return
	var players := Net._players_root()
	if players == null:
		return
	_update_respawns(players, delta)
	var control := _occupancy(players)
	if control != Net.cube_control:
		_held_seconds = 0.0
		Net.set_cube_control(control)
	if control != Net.CubeControl.RED and control != Net.CubeControl.BLUE:
		_held_seconds = 0.0
		return
	_held_seconds += delta
	while _held_seconds + 0.00001 >= 1.0 and Net.cube_round_active():
		_held_seconds = maxf(0.0, _held_seconds - 1.0)
		Net.award_cube_point(Net.PLAYER_SCRIPT.Team.RED if control == Net.CubeControl.RED else Net.PLAYER_SCRIPT.Team.BLUE)


func _occupancy(players: Node) -> Net.CubeControl:
	var red := false
	var blue := false
	var excluded: Array[RID] = []
	for player in players.get_children():
		if player is CollisionObject3D:
			excluded.append(player.get_rid())
	for player in players.get_children():
		if player.is_queued_for_deletion() or player._unconscious or player.movement_locked:
			continue
		if not supports_player(player, excluded):
			continue
		if player.team == Net.PLAYER_SCRIPT.Team.RED:
			red = true
		elif player.team == Net.PLAYER_SCRIPT.Team.BLUE:
			blue = true
	if red and blue:
		return Net.CubeControl.CONTESTED
	if red:
		return Net.CubeControl.RED
	return Net.CubeControl.BLUE if blue else Net.CubeControl.NEUTRAL


func supports_player(player: Node3D, excluded: Array[RID] = []) -> bool:
	if not "body_half_height" in player:
		return false
	if excluded.is_empty():
		for body in get_tree().get_nodes_in_group("player"):
			if body is CollisionObject3D:
				excluded.append(body.get_rid())
	# only feet supported by the cube count
	var origin := player.global_position
	var query := PhysicsRayQueryParameters3D.create(origin,
		origin + Vector3.DOWN * (player.body_half_height + 0.18), _cube.collision_layer, excluded)
	var hit := _cube.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == _cube and hit.normal.dot(Vector3.UP) >= 0.6


func _update_respawns(players: Node, delta: float) -> void:
	for id in _down_seconds.keys():
		if not players.has_node(str(id)):
			_down_seconds.erase(id)
	for player in players.get_children():
		var id := str(player.name).to_int()
		if player.is_queued_for_deletion() or not player._unconscious:
			_down_seconds.erase(id)
			continue
		_down_seconds[id] = _down_seconds.get(id, 0.0) + delta
		if _down_seconds[id] < RESPAWN_SECONDS:
			continue
		_down_seconds.erase(id)
		if Net.is_online():
			Net.rpc("net_cube_respawn", id)
		else:
			Net.net_cube_respawn(id)
