extends RefCounted


static func _detach_camera_rig(player) -> void:
	# deferred a frame by _ready so the body can be gone by the time
	if not player.is_inside_tree() or not is_instance_valid(player._cam_pivot):
		return
	# the scene root not get_parent the player used to sit directly under main so
	var root = player.get_tree().current_scene
	if root:
		player._cam_pivot.reparent(root, true)


static func _shake_change(player, delta: float) -> void:
	if player._shake_left <= 0.0:
		return
	player._shake_left = maxf(player._shake_left - delta, 0.0)
	if player._shake_left <= 0.0 or player._shake_total <= 0.0:
		player._camera.h_offset = 0.0
		player._camera.v_offset = 0.0
		return
	var falloff = player._shake_left / player._shake_total
	player._camera.h_offset = randf_range(-1.0, 1.0) * player._shake_strength * falloff
	player._camera.v_offset = randf_range(-1.0, 1.0) * player._shake_strength * falloff


static func shake_camera(player, strength: float, duration: float) -> void:
	player._shake_strength = strength
	player._shake_total = maxf(duration, 0.001)
	player._shake_left = player._shake_total


static func _camera_pivot_change(player, delta: float) -> void:
	if VR.immersive:
		player._gui_change()
		return
	if not is_instance_valid(player._cam_pivot) or not player._cam_pivot.is_inside_tree():
		return

	var view_transform = player.get_global_transform_interpolated()
	var target_pos = view_transform.origin + Vector3.UP * player._cam_pivot_height
	player._cam_pivot.global_position = player._cam_pivot.global_position.lerp(
		target_pos, 1.0 - exp(-player.camera_follow_speed * delta))
	var target_yaw = view_transform.basis.get_euler().y
	var target_pitch = deg_to_rad(player.default_camera_pitch_deg)
	var target_angles = Vector2(target_yaw, target_pitch)
	if player.using_controller:
		if not Net.input_blocked_by_menu() and not Net.is_spectating():
			var look := Input.get_vector("pad_look_left", "pad_look_right", "pad_look_up", "pad_look_down")
			player.controller_angles.x -= look.x * 2.5 * delta
			player.controller_angles.y = clampf(player.controller_angles.y - look.y * 1.8 * delta, deg_to_rad(-75), deg_to_rad(25))
		target_angles = player.controller_angles
	if not VR.active and Input.is_action_pressed("look_scoreboard"):
		target_angles = player._camera_look_angles(player._scoreboard_look_node(), target_angles)
	var current_yaw = player._cam_pivot.global_transform.basis.get_euler().y
	var new_yaw = lerp_angle(current_yaw, target_angles.x, 1.0 - exp(-player.camera_turn_speed * delta))
	player._cam_pivot.global_rotation.y = new_yaw
	player._camera.rotation.x = lerp_angle(
		player._camera.rotation.x, target_angles.y,
		1.0 - exp(-player.camera_pitch_speed * delta))

	player._gui_change()


static func _camera_look_angles(player, target: Node3D, fallback: Vector2) -> Vector2:
	if target == null:
		return fallback
	var look = target.global_position - player._cam_pivot.global_position
	var flat = Vector3(look.x, 0.0, look.z)
	if flat.length_squared() <= 0.001:
		return fallback
	var flat_dir = flat.normalized()
	var yaw = atan2(-flat_dir.x, -flat_dir.z)
	var local_look = Basis(Vector3.UP, yaw).inverse() * look.normalized()
	var pitch = clampf(
		atan2(local_look.y, -local_look.z),
		deg_to_rad(-75.0),
		deg_to_rad(45.0))
	return Vector2(yaw, pitch)


static func _scoreboard_look_node(player) -> Node3D:
	var scene = player.get_tree().current_scene
	if scene == null:
		return null
	var scoreboard = scene.get_node_or_null("Scoreboard")
	if not (scoreboard is Node3D):
		return null
	var title = scoreboard.get_node_or_null("SCORE")
	if title is Node3D:
		return title
	return scoreboard


static func _gui_change(player) -> void:
	if not player.gui:
		return
	player.gui.get_node("stamina_bar").value = player.stamina
	player.gui.get_node("momentum_bar").value = player.momentum


static func _update_camera_pitch(player) -> void:
	player._camera.rotation.x = deg_to_rad(player.default_camera_pitch_deg)


static func _mouse_aim_direction_3d(player, origin: Vector3) -> Vector3:
	var ray_origin: Vector3
	var ray_direction: Vector3
	if VR.immersive and player._is_local():
		var camera: Camera3D = VR.view_camera(player._camera)
		ray_origin = camera.global_position
		ray_direction = -camera.global_basis.z
	else:
		var mouse: Vector2 = player.Controller.aim_position(player)
		ray_origin = player._camera.project_ray_origin(mouse)
		ray_direction = player._camera.project_ray_normal(mouse)
	var end = ray_origin + ray_direction * 100.0
	var query = PhysicsRayQueryParameters3D.create(ray_origin, end, 1, [player.get_rid()])
	var hit = player.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit.get("position", end)
	var aim = target - origin
	return aim.normalized() if not aim.is_zero_approx() else ray_direction


static func _mouse_aim_direction(player) -> Vector3:
	var mouse_pos: Vector2 = player.Controller.aim_position(player)
	var ray_origin = player._camera.project_ray_origin(mouse_pos)
	var ray_dir = player._camera.project_ray_normal(mouse_pos)
	var plane_y = player._water_height()

	if absf(ray_dir.y) > 0.0001:
		var t = (plane_y - ray_origin.y) / ray_dir.y
		if t > 0.0:
			var hit = ray_origin + ray_dir * t
			var aim = Vector3(hit.x - player.global_position.x, 0.0, hit.z - player.global_position.z)
			if aim.length() > 0.01:
				return aim.normalized()

	var forward = -player.transform.basis.z
	forward.y = 0.0
	return forward.normalized()


static func _ensure_revive_prompt(player) -> Node:
	if is_instance_valid(player._revive_prompt):
		return player._revive_prompt
	if player.gui == null:
		return null
	player._revive_prompt = player._REVIVE_PROMPT.instantiate()
	player.gui.add_child(player._revive_prompt)
	return player._revive_prompt


static func _update_revive_prompt(player) -> void:
	var target = player._revive_target()
	# dont build the prompt just to be told theres nobody to revive a normal
	if target == null and not is_instance_valid(player._revive_prompt):
		return
	var prompt = player._ensure_revive_prompt()
	if prompt:
		prompt.show_for(target, VR.view_camera(player._camera), player.using_controller)


static func _update_movement_prompt(player) -> void:
	if not is_instance_valid(player.gui):
		return
	var action := ""
	if not player._unconscious and not player.movement_locked and not player._hurdling \
			and not player._cannon_ball_active and not player.practice_input_blocked \
			and not Net.input_blocked_by_menu() and not Net.is_spectating() \
			and not Net._round_over and not Net.arcade.controls(player):
		if player.CannonBall.can_start(player):
			action = "Cannon Ball"
		elif player.Movement.hurdle_target(player) != null:
			action = "Hurdle"
	if not is_instance_valid(player._movement_prompt):
		if action.is_empty():
			return
		player._movement_prompt = player._MOVEMENT_PROMPT.instantiate()
		player.gui.add_child(player._movement_prompt)
	player._movement_prompt.show_for(player, VR.view_camera(player._camera), action)


static func _teammates_in_arena(player) -> Array:
	var mates: Array = []
	for other in player.get_tree().get_nodes_in_group("player"):
		if other == player or not is_instance_valid(other):
			continue
		# duck typed same as _revive_target above anything in the player group that has a
		if not ("team" in other) or other.team != player.team:
			continue
		mates.append(other)
	return mates


static func _update_nameplates(player) -> void:
	var wanted = {}
	for other in player._teammates_in_arena():
		if other.practice != null:
			wanted[other.get_instance_id()] = other
			continue
		# the nodes name is the peer id same convention _enter_tree reads on the way
		var pid = str(other.name).to_int()
		if pid > 0:
			wanted[pid] = other

	# drop plates for anyone who no longer qualifies left the arena or never actually
	for pid in player._nameplates.keys():
		if not wanted.has(pid):
			if is_instance_valid(player._nameplates[pid]):
				player._nameplates[pid].queue_free()
			player._nameplates.erase(pid)

	if player.gui == null:
		return
	for pid in wanted:
		if not is_instance_valid(player._nameplates.get(pid)):
			var plate = player._NAMEPLATE.instantiate()
			player.gui.add_child(plate)
			player._nameplates[pid] = plate
		var display_name: String = wanted[pid].practice.display_name if wanted[pid].practice != null else Net.name_of(pid)
		player._nameplates[pid].setup(wanted[pid], VR.view_camera(player._camera), display_name)
