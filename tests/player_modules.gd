extends Node3D

const PLAYER := preload("res://water/player.tscn")
const PLAYER_SCRIPT := preload("res://water/player.gd")
var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var local = _make_player(1)
	var remote = _make_player(2)
	_expect(PLAYER_SCRIPT.Team.RED == 0 and PLAYER_SCRIPT.Team.BLUE == 1, "team ids stay compatible")
	_expect(PLAYER_SCRIPT.WaterMove.values() == [0, 1, 2, 3], "water move ids stay compatible")
	var exported := {}
	for property in local.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR:
			exported[property.name] = true
	for property in ["team", "is_lifeguard", "ocean_path", "jump_speed", "water_counter_stamina_cost", "stamina"]:
		_expect(exported.has(property), "inspector property stays on player " + property)
	for sync_name in ["SpawnSynchronizer", "MultiplayerSynchronizer"]:
		var sync: MultiplayerSynchronizer = local.get_node(sync_name)
		for path in sync.replication_config.get_properties():
			var node := local.get_node(NodePath(path.get_concatenated_names()))
			_expect(node.get_indexed(NodePath(path.get_concatenated_subnames())) != null, "replicated property still resolves " + str(path))
	local.position = Vector3(0, 4, 0)
	_expect(local._submersion() == 0.0, "movement helper reads player position")
	local.stamina = 100.0
	remote.stamina = 100.0
	local.take_stamina_damage(10.0)
	_expect(local.stamina == 90.0 and remote.stamina == 100.0, "helper state stays per player")
	local.team = PLAYER_SCRIPT.Team.BLUE
	local.is_lifeguard = true
	_expect(local.get_node("blockbench_export").has_node("kickboard"), "role changes still replace the rig")
	_expect(local.water_power_damage_max == 60.0 and remote.water_power_damage_max == 30.0, "loadouts stay per player")
	local.play_anim(PLAYER_SCRIPT.AnimationState.WALK)
	_expect(local._anim_player.assigned_animation == "walk", "animation entry point still delegates")
	local.shake_camera(0.1, 1.0)
	_expect(local._shake_left == 1.0 and remote._shake_left == 0.0, "camera shake stays per player")
	local._wall_anim_active = true
	local.net_water_wall_stop()
	_expect(not local._wall_anim_active, "wall stop delegates across combat and appearance")
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var tinted := PLAYER_SCRIPT._tinted_texture(texture, Color.RED)
	_expect(tinted == PLAYER_SCRIPT._tinted_texture(texture, Color.RED), "team texture cache stays shared")
	_expect(tinted.get_image().get_pixel(0, 0).is_equal_approx(Color.RED), "team tint still changes white pixels")
	await get_tree().process_frame
	await get_tree().process_frame
	print("FAIL player modules" if failed else "PASS player modules")
	get_tree().quit(1 if failed else 0)


func _make_player(id: int) -> Node3D:
	var player := PLAYER.instantiate()
	player.name = str(id)
	add_child(player)
	player.freeze = true
	player.set_process(false)
	player.set_physics_process(false)
	return player


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
