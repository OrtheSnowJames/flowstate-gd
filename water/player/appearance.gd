extends RefCounted

const Types = preload("res://water/player/types.gd")
const MovementState = Types.MovementState
const Team = Types.Team
const AnimationState = Types.AnimationState
const ANIM_MAP = Types.ANIM_MAP

static var _tint_cache: Dictionary = {}
const _TEAM_WHITE_CUTOFF := 0.8


static func _apply_lifeguard_loadout(player) -> void:
	if player.is_lifeguard:
		player.water_power_damage_max = player._LIFEGUARD_WATER_POWER_DAMAGE_MAX
		player.water_attack_damage_max = player._LIFEGUARD_WATER_ATTACK_DAMAGE_MAX
		player.momentum_gain_mult = player._LIFEGUARD_MOMENTUM_GAIN_MULT
		player.momentum_loss_mult = player._LIFEGUARD_MOMENTUM_LOSS_MULT
		player.water_wall_block_reduction = player._LIFEGUARD_WATER_WALL_BLOCK_REDUCTION
	else:
		player.water_power_damage_max = player._NORMAL_WATER_POWER_DAMAGE_MAX
		player.water_attack_damage_max = player._NORMAL_WATER_ATTACK_DAMAGE_MAX
		player.momentum_gain_mult = player._NORMAL_MOMENTUM_GAIN_MULT
		player.momentum_loss_mult = player._NORMAL_MOMENTUM_LOSS_MULT
		player.water_wall_block_reduction = player._NORMAL_WATER_WALL_BLOCK_REDUCTION
	player._apply_mesh_for_lifeguard()


static func _apply_mesh_for_lifeguard(player) -> void:
	var old = player.get_node_or_null("blockbench_export")
	if not (old and old.has_node("kickboard") == player.is_lifeguard):
		if old:
			player.remove_child(old)
			old.queue_free()
		var mesh: Node3D = (player._LIFEGUARD_MESH if player.is_lifeguard else player._CHARACTER_MESH).instantiate()
		mesh.name = "blockbench_export"
		# matches player tscns own baked transform for this node exactly both rigs were modeled
		mesh.transform = Transform3D(Basis().scaled(Vector3.ONE * 0.5), Vector3(0.0, -1.0725327, 0.0))
		player.add_child(mesh)
		player._anim_player = player.get_node_or_null("blockbench_export/AnimationPlayer")
		# _movement_anim_state tracks whats playing on a specific animationplayer instance a fresh one from the
		player._movement_anim_state = -1
	# unconditional not just on the swapped branch above a freshly swapped animationplayer needs it
	player._fix_animation_loop_modes()
	# likewise unconditional a swapped in rig arrives with the untouched imported material on every
	player._apply_team_colors()
	if VR.immersive and player._owner_peer > 0 and player._is_local():
		player.get_node("blockbench_export").hide()


static func _apply_team_colors(player) -> void:
	var rig = player.get_node_or_null("blockbench_export")
	if rig == null:
		return
	var color: Color = player._TEAM_COLORS.get(player.team, player._TEAM_COLORS[Team.RED])
	for mesh_inst in player._mesh_instances_in(rig):
		if mesh_inst.mesh == null:
			continue
		for surface in mesh_inst.mesh.get_surface_count():
			# read the material off the mesh resource never the active one get_active_material would resolve
			var base = mesh_inst.mesh.surface_get_material(surface)
			if not (base is StandardMaterial3D) or base.albedo_texture == null:
				continue
			var tinted = player._tinted_texture(base.albedo_texture, color)
			if tinted == null:
				continue
			var mat: StandardMaterial3D = base.duplicate()
			mat.albedo_texture = tinted
			mesh_inst.set_surface_override_material(surface, mat)


static func _mesh_instances_in(player, node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(player._mesh_instances_in(child))
	return found


static func _tinted_texture(source: Texture2D, color: Color) -> ImageTexture:
	var key := [source.get_rid(), color]
	if _tint_cache.has(key):
		return _tint_cache[key]

	var img := source.get_image()
	if img == null:
		return null
	img = img.duplicate()
	# the atlases import as compressed vram textures see the import files get_pixel set_pixel dont
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	img.convert(Image.FORMAT_RGBA8)

	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a > 0.0 and minf(minf(px.r, px.g), px.b) >= _TEAM_WHITE_CUTOFF:
				# keep the source alpha the materials are alpha mask so overwriting it here would
				img.set_pixel(x, y, Color(color.r, color.g, color.b, px.a))

	var tex := ImageTexture.create_from_image(img)
	_tint_cache[key] = tex
	return tex


static func _fix_animation_loop_modes(player) -> void:
	if not player._anim_player:
		return
	var loop_names: Array[String] = ["water_wall", "walk"]
	if not player.is_lifeguard:
		loop_names += player._CHARACTER_LOOP_ANIMS
	for anim_name in loop_names:
		if player._anim_player.has_animation(anim_name):
			player._anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	if player._anim_player.has_animation("cannon_ball"):
		player._anim_player.get_animation("cannon_ball").loop_mode = Animation.LOOP_NONE


static func _apply_replicated_animation(player) -> void:
	if Net.arcade.controls(player):
		return
	if not player._anim_player or player._received_animation.size() != 4:
		return
	var clip: String = player._received_animation[0]
	if clip.is_empty() or not player._anim_player.has_animation(clip):
		return
	var changed = player._anim_player.assigned_animation != clip
	if changed or (player._received_animation[3] and not player._anim_player.is_playing()):
		player._anim_player.play(clip)
	player._anim_player.speed_scale = player._received_animation[2]
	if changed or absf(player._anim_player.current_animation_position - player._received_animation[1]) > 0.15:
		player._anim_player.seek(player._received_animation[1], true)
	if not player._received_animation[3]:
		player._anim_player.pause()


static func anim_name_to_string(_player, anim_name: AnimationState) -> String:
	# looks up the string by enum key falls back to empty string if missing
	return ANIM_MAP.get(anim_name, "")


static func play_anim(player, anim_state: AnimationState) -> void:
	if not player._anim_player:
		return
	if player._movement_anim_state == anim_state:
		return
	player._movement_anim_state = anim_state
	if anim_state == AnimationState.SWIM_UP:
		# start it from the top at a sane rate _apply_swim_up_anim_speed called every frame from
		player._anim_player.speed_scale = 1.0
		player._anim_player.play("swim_up")
		player._apply_swim_up_anim_speed()
	else:
		# anything else runs at its authored rate speed_scale is a property of the whole
		player._anim_player.speed_scale = 1.0
		var clip: String = player.anim_name_to_string(anim_state)
		if anim_state == AnimationState.HURDLE:
			# fit the whole hurdle animation to the climb
			player._anim_player.speed_scale = player._anim_player.get_animation(clip).length / maxf(player.hurdle_duration, 0.01)
		player._anim_player.play(clip)


static func _play_water_action_anim(player, anim_name: String) -> void:
	if not player._anim_player or not player._anim_player.has_animation(anim_name):
		return
	# speed_scale belongs to the whole animationplayer and the swim_up wind up drives it well
	player._anim_player.speed_scale = 1.0
	player._anim_player.play(anim_name)
	player._action_anim_lock_movement_state = player.movement_state
	# this clip now owns the animationplayer instead of play_anim s own bookkeeping invalidate it
	player._movement_anim_state = -1


static func _play_water_wall_anim(player) -> void:
	if not player._anim_player or not player._anim_player.has_animation("water_wall"):
		return
	if player._anim_player.current_animation != "water_wall":
		# same reset same reason as _play_water_action_anim a wind up interrupted by raising the wall
		player._anim_player.speed_scale = 1.0
		player._anim_player.play("water_wall")
	player._wall_anim_active = true
	player._movement_anim_state = -1 # same reasoning as _play_water_action_anim


static func _stop_water_wall_anim(player) -> void:
	player._wall_anim_active = false


static func _anim_change(player) -> void:
	if Net.arcade.controls(player):
		return
	if player.movement_state == MovementState.DODGE:
		return # todo handle in dodge functions
	if not player._anim_player:
		return

	# out cold the death animation holds on its last frame and nothing should take
	if player._unconscious:
		return

	# water_wall looping and water_power water_attack hold on last frame are playing themselves directly see
	if player._wall_anim_active:
		return
	if player._action_anim_lock_movement_state == player.movement_state:
		return
	player._action_anim_lock_movement_state = -1

	match player.movement_state:
		MovementState.IDLE:
			player.play_anim(AnimationState.IDLE)
		MovementState.TREAD:
			player.play_anim(AnimationState.TREAD)
		MovementState.SWIM_UP:
			player.play_anim(AnimationState.SWIM_UP)
			# every frame not just on the state change the wind up its being fitted
			player._apply_swim_up_anim_speed()
		MovementState.SWIM:
			player.play_anim(AnimationState.SWIM)
		MovementState.GLIDE:
			player.play_anim(AnimationState.GLIDE)
		MovementState.WALK:
			player.play_anim(AnimationState.WALK)
		MovementState.JUMP:
			player.play_anim(AnimationState.JUMP)
		MovementState.HURDLE:
			player.play_anim(AnimationState.HURDLE)
		MovementState.CANNON_BALL:
			player.play_anim(AnimationState.CANNON_BALL)


static func _apply_swim_up_anim_speed(player) -> void:
	if not player._anim_player or not player._anim_player.has_animation("swim_up"):
		return
	# reads once a loop_none clip has finished and is holding its last frame nothing
	if player._anim_player.current_animation != "swim_up":
		return
	var anim = player._anim_player.get_animation("swim_up")
	var clip_len = anim.length if anim else 0.0
	if clip_len <= 0.0:
		clip_len = player.SWIM_UP_ANIMATION_BASE_TIME
	var clip_left = maxf(clip_len - player._anim_player.current_animation_position, 0.0)
	var time_left = player._swim_up_time_remaining()
	if clip_left <= 0.0 or time_left <= 0.0:
		player._anim_player.speed_scale = 1.0
		return
	# clamped right at the threshold time_left goes to zero and an unclamped ratio would
	player._anim_player.speed_scale = clampf(
		clip_left / time_left, player._SWIM_UP_MIN_SPEED, player._SWIM_UP_MAX_SPEED)
