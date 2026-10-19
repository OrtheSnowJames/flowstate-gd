extends Node

const Gestures := preload("res://vr/gestures.gd")
const Arms := preload("res://water/player/vr_arms.gd")
const SWIM_MOMENTUM_GAIN := 2.0
const SWIM_MOMENTUM_LOSS := 0.5
const STROKE_RECOVERY_TIME := 1.3
var gestures := Gestures.new()
var origin: XROrigin3D
var head: Camera3D
var panel: MeshInstance3D
var blur: MeshInstance3D
var fade: MeshInstance3D
var player: Node3D
var swim_enabled := false
var hand_mode := Gestures.HandMode.NEUTRAL
var stroke_boost := 0.0
var _scene: Node
var _yaw := 0.0
var _center := Vector3.ZERO
var _wall_time := 0.0
var _wall_refresh := 0.0
var _was_blocked := true
var _last_position := Vector3.ZERO
var _eye: ColorRect
var _eye_visible := true
var _blur_visible := true
var _fade_visible := true
var _pending_mode := Gestures.HandMode.NEUTRAL
var _mode_time := 0.0
var _tracking_lost := 0.0
var _tracking_time := 0.0
var _hand_poses: Array = [null, null]
var _hand_seen: Array[float] = [-100.0, -100.0]


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
	_tracking_time += delta
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
		_hand_poses = [null, null]
		_hand_seen = [-100.0, -100.0]
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
		origin.position = player.get_global_transform_interpolated().origin + Vector3.UP * Arms.EYE_HEIGHT - origin.basis * _center
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
	update_hand_mode(delta)


func can_gesture() -> bool:
	return is_instance_valid(player) and not player._unconscious and not player.movement_locked \
		and not Net.is_spectating() and not Net.input_blocked_by_menu() and not Net.arcade.controls(player) and player._ocean != null


func update_hand_mode(delta := 0.0) -> void:
	if not can_gesture():
		cancel_gestures()
		return
	var tracked := false
	for hand in VR._hands:
		tracked = tracked or hand.get_is_active()
	_tracking_lost = 0.0 if tracked else _tracking_lost + delta
	if _tracking_lost >= 0.4:
		cancel_gestures()
		return
	var next := Gestures.HandMode.NEUTRAL
	if VR._hands.size() == 2 and VR._hands[0].get_is_active() and VR._hands[1].get_is_active():
		next = Gestures.hand_mode(hand_transform(VR._hands[0]), hand_transform(VR._hands[1]), hand_mode)
	# stop adding swim momentum as soon as the controllers no longer face each other
	if hand_mode == Gestures.HandMode.SWIM and next != Gestures.HandMode.SWIM:
		cancel_gestures()
	if next == Gestures.HandMode.NEUTRAL:
		_pending_mode = next
		_mode_time = 0.0
		return
	if next != _pending_mode:
		_pending_mode = next
		_mode_time = 0.0
	_mode_time += delta
	var settle_time := 0.2 if next == Gestures.HandMode.SWIM else 0.12
	if next != hand_mode and _mode_time >= settle_time:
		cancel_gestures()
		hand_mode = next
		swim_enabled = next == Gestures.HandMode.SWIM


func hand_transform(hand: XRController3D) -> Transform3D:
	return hand.global_transform


func body_pose(body, network := true) -> Array:
	if body != player or Net.is_spectating():
		return []
	var inverse: Transform3D = body.global_transform.affine_inverse()
	var head_pose := (inverse * head.global_transform).orthonormalized()
	if not head_pose.is_finite():
		return []
	var result: Array = [head_pose, head_pose, head_pose, 0]
	for i in range(mini(VR._hands.size(), 2)):
		var hand: XRController3D = VR._hands[i]
		if hand.get_is_active() and hand.transform.is_finite():
			_hand_poses[i] = hand.transform.orthonormalized()
			_hand_seen[i] = _tracking_time
		if _hand_poses[i] != null and _tracking_time - _hand_seen[i] < 0.4:
			var wrist: Transform3D = (inverse * origin.global_transform * _hand_poses[i]).orthonormalized()
			if network and (wrist.origin.length() > 3.0 or wrist.origin.distance_to(head_pose.origin) > 1.8):
				continue
			result[i + 1] = wrist
			result[3] |= 1 << i
	return result if not network or Arms.valid_pose(result) else []


func combat(body, delta: float) -> void:
	if body != player or not can_gesture():
		cancel_gestures()
		return
	update_hand_mode()
	stroke_boost = maxf(0.0, stroke_boost - delta)
	if hand_mode == Gestures.HandMode.NEUTRAL:
		return
	_wall_time = maxf(0.0, _wall_time - delta)
	_wall_refresh = maxf(0.0, _wall_refresh - delta)
	var movement := Input.get_axis("pad_move_up", "pad_move_down")
	var heading := Basis(Vector3.UP, head.rotation.y)
	var events: Array[Dictionary] = []
	for i in range(VR._hands.size()):
		var hand: XRController3D = VR._hands[i]
		var at := hand_transform(hand).origin
		# gestures use the players water contact instead of a thin controller height band
		var wet: bool = body._submersion() > 0.0 and at.y <= head.global_position.y + 0.15
		var event := gestures.sample(i, hand.position, wet, hand.get_is_active(), movement, delta, heading, hand_mode)
		if not event.is_empty():
			event["at"] = at
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
	if not can_gesture() or body != player:
		return
	if event.kind == "stroke" and hand_mode != Gestures.HandMode.SWIM:
		return
	if event.kind != "stroke" and hand_mode != Gestures.HandMode.ATTACK:
		return
	match event.kind:
		"stroke":
			if body.stamina > 0.0:
				# leave time to return the arm for the next stroke
				stroke_boost = STROKE_RECOVERY_TIME
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
	_pending_mode = Gestures.HandMode.NEUTRAL
	_mode_time = 0.0
	hand_mode = Gestures.HandMode.NEUTRAL
	swim_enabled = false
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
	update_hand_mode()
	var input := Input.get_vector("pad_move_left", "pad_move_right", "pad_move_up", "pad_move_down")
	body.can_move = true
	if input.is_zero_approx() and stroke_boost > 0.0 and swim_enabled:
		input = Vector2.UP
	var moving := input.length() > 0.1
	if moving:
		body.dir = Basis(Vector3.UP, head.global_rotation.y) * Vector3(input.x, 0, input.y)
	var target: float = body.max_momentum * (1.0 if stroke_boost > 0.0 else 0.45) if moving and swim_enabled else 0.0
	var gain: float = SWIM_MOMENTUM_GAIN if target > body.momentum else SWIM_MOMENTUM_LOSS
	body.momentum = move_toward(body.momentum, target, gain * delta)
	body.movement_state = body.MovementState.SWIM if moving and swim_enabled else body.MovementState.GLIDE
	if body.momentum <= 0.0:
		body.movement_state = body.MovementState.TREAD
		body.dir = Vector3.ZERO
	body._apply_swim_motion(body.dir, body.momentum / body.max_momentum)
