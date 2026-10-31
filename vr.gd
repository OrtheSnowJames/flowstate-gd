extends Node

signal mode_changed

const DEVICE := 15
const ESCAPE_HOLD_SECONDS := 0.6
const TRIGGER_CHORD_SECONDS := 0.12
var active := false
var immersive := false
var entering := false
var exiting := false
var immersion: Node
var quest_standalone := false
var room_view: SubViewport
var _interface: XRInterface
var _hands: Array[XRController3D] = []
var _buttons: Dictionary = {}
var _axes: Dictionary = {}
var _actions: Dictionary = {}
var _pelt_triggers: Array[bool] = [false, false]
var _pelt_hand := -1
var _pending_pelt_hand := -1
var _pelt_wait := 0.0
var _escape_hold := 0.0
var _escape_engaged := false
var _escape_fired := false
var _origin: XROrigin3D
var _head: Camera3D
var _room_root: Node3D
var _room: Node3D
var _environment: WorldEnvironment
var _room_environment: Environment
var _light: OmniLight3D
var _zoom: Tween
var _saved_transparent := false
var _saved_disable_3d := false
var _room_needs_center := false


func _ready() -> void:
	_interface = XRServer.find_interface("OpenXR")
	if _interface is OpenXRInterface:
		_interface.pose_recentered.connect(_request_room_center)
	var info := str(_interface.get_system_info()) if _interface and _interface.is_initialized() else ""
	quest_standalone = is_standalone_quest(OS.get_name(), OS.get_model_name(), info, OS.has_feature("quest"))
	_apply_quest_fps_limit()
	if "--vr-preview" in OS.get_cmdline_user_args():
		call_deferred("start", true)
	elif _interface and _interface.is_initialized():
		call_deferred("start")


static func is_standalone_quest(platform: String, model: String, runtime: String, quest_export := false) -> bool:
	if platform != "Android":
		return false
	var identity := (model + " " + runtime).to_lower()
	return quest_export or "quest" in identity or "oculus" in identity or "meta" in identity


func _apply_quest_fps_limit() -> void:
	if quest_standalone:
		Settings.apply_frame_limit()

# split up start into start_init and ready_room
func start_init(preview := false) -> bool:
	if active:
		return true
	if not preview and (_interface == null or (not _interface.is_initialized() and not _interface.initialize())):
		return false
	if not preview:
		_interface.interface_is_primary = true
		quest_standalone = is_standalone_quest(OS.get_name(), OS.get_model_name(), str(_interface.get_system_info()), OS.has_feature("quest"))
	_apply_quest_fps_limit()
	return true

func start(preview := false) -> bool:
	if not start_init(preview):
		return false
	if not ready_room(preview):
		return false
	return true

func ready_room(preview := false) -> bool:
	if room_view != null:
		return true
	room_view = SubViewport.new()
	room_view.name = "VRRoomView"
	room_view.own_world_3d = true
	room_view.audio_listener_enable_3d = true
	room_view.size = Vector2i(1280, 720)
	room_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	room_view.use_xr = not preview
	add_child(room_view)
	_room_root = load("res://water/vr_room.tscn").instantiate()
	room_view.add_child(_room_root)
	_room = _room_root.get_node("Room")
	var screen: MeshInstance3D = _room.get_node("GameScreen")
	screen.material_override.albedo_texture = get_tree().root.get_texture()
	_environment = _room_root.get_node("WorldEnvironment")
	_room_environment = _environment.environment
	_light = _room_root.get_node("RoomLight")
	_origin = _room_root.get_node("XROrigin3D")
	_head = _origin.get_node("PreviewCamera" if preview else "XRCamera3D")
	_head.make_current()
	if preview:
		_origin.get_node("XRCamera3D").free()
	else:
		_origin.get_node("PreviewCamera").free()
		_hands.assign([_origin.get_node("LeftHand"), _origin.get_node("RightHand")])
	active = true
	_room_needs_center = not preview
	mode_changed.emit()
	return true


func _request_room_center() -> void:
	if active and not immersive and not entering and not exiting:
		if _head is not XRCamera3D:
			_place_in_room(_head.transform)
			return
		_room_needs_center = true


func _center_room_from_tracking() -> void:
	var tracker := XRServer.get_tracker("head") as XRPositionalTracker
	if tracker == null:
		return
	var pose := tracker.get_pose("default")
	if pose == null or not pose.has_tracking_data:
		return
	_place_in_room(pose.get_adjusted_transform())
	_room_needs_center = false


func _place_in_room(head_pose: Transform3D) -> void:
	var seat: Transform3D = _room.get_node("SeatEye").global_transform.orthonormalized()
	if CouchParty.active():
		seat = CouchParty.seat_transform(CouchParty.local_seat())
	var forward := -head_pose.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.UP.cross(head_pose.basis.x)
	var facing := -seat.basis.z
	facing.y = 0.0
	var yaw := forward.signed_angle_to(facing, Vector3.UP)
	var orientation := Basis(Vector3.UP, yaw)
	# offset the tracking space once so leaning and walking still work
	_origin.global_transform = Transform3D(orientation, seat.origin - orientation * head_pose.origin)


func enter_immersive() -> void:
	if not active or immersive or entering or exiting:
		return
	CouchParty.leave()
	entering = true
	_release_controls()
	_room_needs_center = false
	var target: Vector3 = _room.get_node("GameScreen/ImmersiveEntry").global_position - _origin.global_basis * _head.position
	_zoom = create_tween()
	_zoom.tween_property(_origin, "global_position", target, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await _zoom.finished
	if not active:
		return
	_room_root.remove_child(_room)
	_light.hide()
	_environment.environment = null
	# keep the old world alive until the viewport releases its render scenario
	var previous_world := room_view.find_world_3d()
	room_view.own_world_3d = false
	room_view.audio_listener_enable_3d = false
	room_view.world_3d = get_tree().root.world_3d
	previous_world = null
	_saved_disable_3d = get_tree().root.disable_3d
	_saved_transparent = get_tree().root.transparent_bg
	get_tree().root.disable_3d = true
	get_tree().root.transparent_bg = true
	immersion = preload("res://vr/immersive.gd").new()
	add_child(immersion)
	immersion.setup(_origin, _head)
	immersive = true
	entering = false
	for action in ["water_attack", "water_power", "water_wall", "water_pelt", "water_counter", "swim_key"]:
		_action(action, false)
	mode_changed.emit()


func exit_immersive() -> void:
	if not active or not immersive or entering or exiting:
		return
	exiting = true
	_release_controls()
	immersion.cancel_gestures()
	immersion.set_process(false)
	var cover: MeshInstance3D = immersion.fade
	cover.show()
	_zoom = create_tween()
	_zoom.tween_property(cover.material_override, "albedo_color:a", 1.0, 0.18)
	await _zoom.finished
	if not active:
		return
	immersion.restore_overlays()
	immersion.panel.hide()
	immersion.blur.hide()
	get_tree().root.disable_3d = _saved_disable_3d
	get_tree().root.transparent_bg = _saved_transparent
	immersive = false
	# return the headset to a separate room while the game goes back onto the tv
	room_view.world_3d = null
	room_view.own_world_3d = true
	room_view.audio_listener_enable_3d = true
	_room_root.add_child(_room)
	_environment.environment = _room_environment
	_room_root.apply_lighting()
	_place_in_room(_head.transform)
	var seat := _origin.global_position
	_origin.global_position = _room.get_node("GameScreen/ImmersiveEntry").global_position - _origin.global_basis * _head.position
	mode_changed.emit()
	_zoom = create_tween().set_parallel(true)
	_zoom.tween_property(_origin, "global_position", seat, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_zoom.tween_property(cover.material_override, "albedo_color:a", 0.0, 0.25)
	await _zoom.finished
	if not active:
		return
	_clear_immersion()
	exiting = false


func _clear_immersion() -> void:
	if not is_instance_valid(immersion):
		return
	immersion.teardown()
	immersion.queue_free()
	immersion = null
	get_tree().root.disable_3d = _saved_disable_3d
	get_tree().root.transparent_bg = _saved_transparent


func _release_controls() -> void:
	if is_instance_valid(_room_root):
		_room_root.reset_pointers()
	_escape_hold = 0.0
	_escape_engaged = false
	_escape_fired = false
	_pelt_triggers = [false, false]
	_pelt_hand = -1
	_pending_pelt_hand = -1
	_pelt_wait = 0.0
	for action in _actions.keys():
		_action(action, false)
	for button in _buttons.keys():
		_button(button, false)
	for axis in _axes.keys():
		_axis(axis, 0.0)


func body_pose(player) -> Array:
	return immersion.body_pose(player) if immersive and is_instance_valid(immersion) else []


func view_camera(fallback: Camera3D) -> Camera3D:
	return _head if immersive else fallback


func project_ui_position(world: Vector3, fallback: Camera3D) -> Vector2:
	if not immersive:
		return fallback.unproject_position(world)
	var local := _head.to_local(world)
	var point := Vector2(local.x, -local.y) * 2.0 / maxf(-local.z, 0.01)
	return (point / immersion.panel.mesh.size + Vector2(0.5, 0.5)) * get_tree().root.get_visible_rect().size


func stop() -> void:
	CouchParty.leave()
	if _zoom and _zoom.is_running():
		_zoom.kill()
	_clear_immersion()
	immersive = false
	entering = false
	exiting = false
	_room_needs_center = false
	_release_controls()
	_hands.clear()
	if is_instance_valid(_room) and _room.get_parent() == null:
		_room.queue_free()
	if is_instance_valid(room_view):
		room_view.use_xr = false
		room_view.queue_free()
	room_view = null
	_room_root = null
	_room = null
	_room_environment = null
	active = false
	mode_changed.emit()


func _process(delta: float) -> void:
	if entering or exiting:
		return
	if active and _room_needs_center and not immersive and not entering:
		_center_room_from_tracking()
	if not active or _hands.size() != 2:
		return
	var left_click := _hands[0].get_is_active() and _hands[0].is_button_pressed("primary_click")
	var right_click := _hands[1].get_is_active() and _hands[1].is_button_pressed("primary_click")
	var escape_chord := _update_escape_chord(left_click, right_click, delta)
	var menus := not ControllerNavigation._controls().is_empty()
	if not immersive:
		_room_root.update_pointers(delta, menus)
		if entering or exiting or not active:
			return
	var pointer_menu := menus and not immersive
	var arcade := Net.game_mode == Net.GameMode.ARCADE
	var pelt_hand := -1
	for i in range(2):
		var hand := _hands[i]
		var tracked := hand.get_is_active()
		var stick := hand.get_vector2("primary") if tracked else Vector2.ZERO
		_axis(i * 2, 0.0 if pointer_menu else stick.x)
		_axis(i * 2 + 1, 0.0 if pointer_menu or (immersive and i == 1) else -stick.y)
		var ax := tracked and hand.is_button_pressed("ax_button")
		var by := tracked and hand.is_button_pressed("by_button")
		_button(JOY_BUTTON_A if i == 1 else JOY_BUTTON_X, ax if menus and not pointer_menu else false)
		_button(JOY_BUTTON_B if i == 1 else JOY_BUTTON_Y, by if menus and not pointer_menu else false)
		_action("jump" if i == 1 else "water_attack", ax and not menus and (not immersive or i == 1))
		_action("water_power" if i == 1 else "water_wall", by and not menus and not immersive)
		var click := tracked and hand.is_button_pressed("primary_click") and not menus and not escape_chord
		if immersive and i == 0 and not arcade:
			click = false
		_action("revive" if i == 1 else "swim_key", click)
		_action("vr_dodge_right" if i == 1 else "vr_dodge_left", tracked and hand.get_float("grip") > 0.65 and not menus)
		var trigger := tracked and hand.get_float("trigger") > 0.65
		var pointing: bool = not immersive and _room_root.pointer_captured(i)
		_action("arcade_e" if i == 1 else "arcade_q", trigger and arcade and not menus and not pointing)
		if pelt_hand < 0 and trigger and not _pelt_triggers[i] and not arcade and not menus and not pointing:
			pelt_hand = i
		_pelt_triggers[i] = trigger
	_action("water_pelt", false)
	if menus or Net.game_mode == Net.GameMode.ARCADE or wall_triggers_held():
		_pending_pelt_hand = -1
		_pelt_hand = -1
		_pelt_wait = 0.0
		pelt_hand = -1
	elif immersive:
		if pelt_hand >= 0:
			_pending_pelt_hand = pelt_hand
			_pelt_wait = TRIGGER_CHORD_SECONDS
			pelt_hand = -1
		elif _pending_pelt_hand >= 0:
			_pelt_wait -= delta
			if _pelt_wait <= 0.0:
				pelt_hand = _pending_pelt_hand
				_pending_pelt_hand = -1
	if pelt_hand >= 0:
		_pelt_hand = pelt_hand
		_action("water_pelt", true)
	_action("water_counter", false)


func wall_triggers_held() -> bool:
	return immersive and _hands.size() == 2 and Net.game_mode != Net.GameMode.ARCADE \
		and _hands[0].get_is_active() and _hands[1].get_is_active() \
		and _hands[0].get_float("trigger") > 0.65 and _hands[1].get_float("trigger") > 0.65


func _update_escape_chord(left: bool, right: bool, delta: float) -> bool:
	if not left and not right:
		_escape_hold = 0.0
		_escape_engaged = false
		_escape_fired = false
		return false
	if left and right:
		_escape_engaged = true
		_escape_hold += delta
		if _escape_hold >= ESCAPE_HOLD_SECONDS and not _escape_fired:
			_escape_fired = true
			_action("ui_cancel", true)
			_action("ui_cancel", false)
	else:
		_escape_hold = 0.0
	return _escape_engaged


func _action(action: String, pressed: bool) -> void:
	if _actions.get(action, false) == pressed:
		return
	_actions[action] = pressed
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _button(button: int, pressed: bool) -> void:
	if _buttons.get(button, false) == pressed:
		return
	_buttons[button] = pressed
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _axis(axis: int, value: float) -> void:
	if is_equal_approx(float(_axes.get(axis, 0.0)), value):
		return
	_axes[axis] = value
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
