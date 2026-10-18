extends Node

const Gestures := preload("res://vr/gestures.gd")
var gestures := Gestures.new()
var origin: XROrigin3D
var head: Camera3D
var panel: MeshInstance3D
var blur: MeshInstance3D
var fade: MeshInstance3D
var player: Node3D
var swim_enabled := false
var stroke_boost := 0.0
var _scene: Node
var _yaw := 0.0
var _center := Vector3.ZERO
var _wall_time := 0.0
var _wall_refresh := 0.0
var _left_down := false
var _click_chord := false
var _was_blocked := true
var _last_position := Vector3.ZERO
var _eye: ColorRect
var _eye_visible := true
var _blur_visible := true
var _fade_visible := true


func setup(xr_origin: XROrigin3D, camera: Camera3D) -> void:
	origin = xr_origin
	head = camera
	_center = head.position
	process_priority = -10
	panel = MeshInstance3D.new()
	panel.name = "ImmersiveUI"
	panel.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 100
	material.albedo_texture = get_tree().root.get_texture()
	panel.material_override = material
	head.add_child(panel)
	panel.position.z = -2.0
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blur = MeshInstance3D.new()
	blur.mesh = QuadMesh.new()
	blur.mesh.size = Vector2(100, 100)
	var blur_material := ShaderMaterial.new()
	blur_material.shader = preload("res://vr/menu_blur.gdshader")
	blur_material.render_priority = 90
	blur.material_override = blur_material
	blur.position.z = -2.1
	blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(blur)
	fade = MeshInstance3D.new()
	fade.mesh = QuadMesh.new()
	fade.mesh.size = Vector2(100, 100)
	var fade_material := StandardMaterial3D.new()
	fade_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_material.no_depth_test = true
	fade_material.render_priority = 110
	fade_material.albedo_color = Color(0, 0, 0, 0)
	fade.material_override = fade_material
	fade.position.z = -1.8
	fade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(fade)
	_blur_visible = Transition._blur_rect.visible
	_fade_visible = Transition._fade_rect.visible
	Transition._blur_rect.hide()
	Transition._fade_rect.hide()


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	var candidate: Node3D
	for body in get_tree().get_nodes_in_group("player"):
		if body._owner_peer > 0 and body._is_local():
			candidate = body
			break
	if scene != _scene or candidate != player:
		cancel_gestures()
		if is_instance_valid(_eye):
			_eye.visible = _eye_visible
		_scene = scene
		player = candidate
		_eye = player._eyelid if player else null
		if _eye:
			_eye_visible = _eye.visible
			_eye.hide()
		swim_enabled = false
		_center = head.position
		_yaw = player.global_rotation.y if player else 0.0
		_last_position = player.global_position if player else Vector3.ZERO
	var menus: bool = (player == null and not Net.is_spectating()) or Net.input_blocked_by_menu()
	var amount: float = maxf(1.0 if menus else 0.0, Transition._blur_mat.get_shader_parameter("amount"))
	blur.visible = amount > 0.001
	blur.material_override.set_shader_parameter("amount", amount)
	var darkness: float = Transition._fade_rect.color.a
	if is_instance_valid(_eye) and _eye.material and not Net.is_spectating():
		darkness = maxf(darkness, _eye.material.get_shader_parameter("progress"))
	fade.visible = darkness > 0.001
	fade.material_override.albedo_color = Color(0, 0, 0, darkness)
	var size := get_tree().root.get_visible_rect().size
	panel.mesh.size = Vector2(2.6, 2.6 * size.y / maxf(size.x, 1.0))
	if is_instance_valid(player) and not Net.is_spectating():
		if player.global_position.distance_to(_last_position) > 5.0:
			cancel_gestures()
			swim_enabled = false
			_yaw = player.global_rotation.y
		_last_position = player.global_position
		if not menus and not player._unconscious and not player.movement_locked:
			_yaw -= Input.get_axis("pad_look_left", "pad_look_right") * 2.2 * delta
		origin.rotation = Vector3(0, _yaw, 0)
		origin.position = player.get_global_transform_interpolated().origin + Vector3.UP * 0.55 - origin.basis * _center
		player.using_controller = true
		player.controller_angles = Vector2(head.global_rotation.y, 0)
	else:
		var camera := get_tree().root.get_camera_3d()
		if camera:
			origin.rotation = camera.global_rotation
			origin.position = camera.global_position - origin.basis * _center
	var blocked := not can_gesture()
	if blocked and not _was_blocked:
		cancel_gestures()
	_was_blocked = blocked


func can_gesture() -> bool:
	return is_instance_valid(player) and not player._unconscious and not player.movement_locked \
		and not Net.is_spectating() and not Net.input_blocked_by_menu() and not Net.arcade.controls(player) and player._ocean != null


func swim_click(left: bool, right: bool, chord: bool) -> void:
	if right or chord:
		_click_chord = true
	if _left_down and not left and not _click_chord and can_gesture():
		swim_enabled = not swim_enabled
	_left_down = left
	if not left and not right:
		_click_chord = false


func body_pose(body) -> Array:
	if body != player or Net.is_spectating():
		return []
	var inverse: Transform3D = body.global_transform.affine_inverse()
	var result: Array = [inverse * head.global_transform, Transform3D.IDENTITY, Transform3D.IDENTITY, 0]
	for i in range(VR._hands.size()):
		if VR._hands[i].get_is_active():
			result[i + 1] = inverse * VR._hands[i].global_transform
			result[3] |= 1 << i
		else:
			result[i + 1] = result[0]
	return result if preload("res://water/player/vr_arms.gd").valid_pose(result) else []


func combat(body, delta: float) -> void:
	if body != player or not can_gesture():
		cancel_gestures()
		return
	stroke_boost = maxf(0.0, stroke_boost - delta)
	_wall_time = maxf(0.0, _wall_time - delta)
	_wall_refresh = maxf(0.0, _wall_refresh - delta)
	var movement := Input.get_axis("pad_move_up", "pad_move_down")
	var heading := Basis(Vector3.UP, head.rotation.y)
	var events: Array[Dictionary] = []
	for i in range(VR._hands.size()):
		var hand: XRController3D = VR._hands[i]
		var wet: bool = absf(hand.global_position.y - body._water_height()) <= 0.45 and body._submersion() > 0.0
		var event := gestures.sample(i, hand.position, wet, hand.get_is_active(), movement, delta, heading)
		if not event.is_empty():
			event["at"] = hand.global_position
			events.append(event)
	# walls take priority when both hands finish a gesture together
	for kind in ["wall", "stroke", "wave"]:
		for event in events:
			if event.kind == kind:
				apply_gesture(body, event, event.at)
	if _wall_time > 0.0 and body.stamina > 0.0 and body._submersion() > 0.0:
		if _wall_refresh <= 0.0:
			var aim := -Basis(Vector3.UP, head.global_rotation.y).z
			var at: Vector3 = body.global_position + aim * 1.2
			at.y = body._water_height()
			body._cast_water_wall(at, aim, 1.0)
			_wall_refresh = 0.1
		body.stamina = maxf(0.0, body.stamina - body.water_wall_stamina_cost_per_second * delta)
	elif body._water_wall_up:
		body._cast_water_wall_stop()


func apply_gesture(body, event: Dictionary, at: Vector3) -> void:
	match event.kind:
		"stroke":
			if body.stamina > 0.0:
				stroke_boost = minf(stroke_boost + 0.65, 1.3)
		"wall":
			if body.stamina > 0.0:
				_wall_time = 0.65
		"wave":
			if _wall_time > 0.0 or body._water_wall_up or body._water_power_cooldown_timer > 0.0 \
					or body.stamina < body.water_power_stamina_cost:
				return
			var aim: Vector3 = Basis(Vector3.UP, head.global_rotation.y) * event.direction
			aim.y = 0.0
			at.y = body._water_height()
			body._cast_water_move(body.WaterMove.POWER, at, aim.normalized(), Gestures.wave_strength(event.distance))
			body.stamina -= body.water_power_stamina_cost
			body._water_power_cooldown_timer = body.water_power_cooldown


func cancel_gestures() -> void:
	gestures.reset()
	stroke_boost = 0.0
	_wall_time = 0.0
	_wall_refresh = 0.0
	if is_instance_valid(player) and player._water_wall_up:
		player._cast_water_wall_stop()


func restore_overlays() -> void:
	Transition._blur_rect.visible = _blur_visible
	Transition._fade_rect.visible = _fade_visible
	if is_instance_valid(_eye):
		_eye.visible = _eye_visible


func swim(body, delta: float) -> void:
	var input := Input.get_vector("pad_move_left", "pad_move_right", "pad_move_up", "pad_move_down")
	body.can_move = true
	body.dir = Basis(Vector3.UP, head.global_rotation.y) * Vector3(input.x, 0, input.y)
	var moving := input.length() > 0.1
	var target: float = body.max_momentum * (1.0 if stroke_boost > 0.0 else 0.45) if moving else 0.0
	body.momentum = move_toward(body.momentum, target, body.SWIM_GAIN * delta * 2.0)
	body.movement_state = body.MovementState.SWIM if moving else body.MovementState.TREAD
	body._apply_swim_motion(body.dir, body.momentum / body.max_momentum)
