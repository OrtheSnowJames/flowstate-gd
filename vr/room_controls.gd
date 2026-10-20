extends Node3D

@export var lights_on := true

var _ambient_energy := 0.8
var _background_color := Color.BLACK
var _triggers: Array[bool] = [false, false]
var _tracked: Array[bool] = [false, false]
var _captured: Array[bool] = [false, false]
var _pressed_hand := -1
var _active_hand := 1
var _mouse_over := false
var _mouse_position := Vector2(-1000, -1000)
var _scroll_wait := 0.0
@onready var _screen: MeshInstance3D = $Room/GameScreen
@onready var _switch: Area3D = $Room/LightSwitch
@onready var _environment: Environment = $WorldEnvironment.environment
@onready var _hands: Array[XRController3D] = [$XROrigin3D/LeftHand, $XROrigin3D/RightHand]


func _ready() -> void:
	_ambient_energy = _environment.ambient_light_energy
	_background_color = _environment.background_color
	apply_lighting()


func apply_lighting() -> void:
	$RoomLight.visible = lights_on
	_environment.ambient_light_energy = _ambient_energy if lights_on else 0.0
	_environment.background_color = _background_color if lights_on else Color.BLACK
	$Room/GameScreen/TVGlow.visible = not lights_on
	$Room/LightSwitch/Rocker.rotation.x = -0.18 if lights_on else 0.18


func pointer_captured(hand: int) -> bool:
	return _captured[hand]


func update_pointers(delta: float, menus: bool) -> void:
	var was_tracked := _tracked.duplicate()
	var targets: Array = [null, null]
	var positions := [Vector2(-1000, -1000), Vector2(-1000, -1000)]
	var triggers: Array[bool] = [false, false]
	_scroll_wait = maxf(0.0, _scroll_wait - delta)
	for i in range(2):
		var hand := _hands[i]
		var pointer: Node3D = hand.get_node("Pointer")
		var aim = _aim_pose(hand)
		pointer.visible = aim != null
		_tracked[i] = pointer.visible
		triggers[i] = pointer.visible and hand.get_float("trigger") > 0.65
		if not pointer.visible:
			_captured[i] = false
			continue
		pointer.global_transform = aim
		var ray: RayCast3D = pointer.get_node("Ray")
		ray.force_raycast_update()
		var distance := ray.target_position.length()
		if ray.is_colliding():
			targets[i] = ray.get_collider()
			distance = pointer.global_position.distance_to(ray.get_collision_point())
			if targets[i] == _screen.get_node("Hitbox"):
				var local := _screen.to_local(ray.get_collision_point())
				positions[i] = Vector2(local.x / _screen.mesh.size.x + 0.5, 0.5 - local.y / _screen.mesh.size.y) * get_tree().root.get_visible_rect().size
				if not menus:
					targets[i] = null
		var beam: MeshInstance3D = pointer.get_node("Beam")
		beam.position.z = -distance * 0.5
		beam.scale.y = maxf(distance, 0.001)
		pointer.get_node("Tip").position.z = -distance
		pointer.get_node("Tip").visible = targets[i] != null
		_captured[i] = targets[i] != null or _pressed_hand == i or (_captured[i] and triggers[i])

	# one hand owns the mouse until it releases the trigger
	if _pressed_hand >= 0:
		var owner := _pressed_hand
		_move_mouse(positions[owner] if menus else Vector2(-1000, -1000))
		if not triggers[owner] or not menus:
			_pressed_hand = -1
			_mouse_button(MOUSE_BUTTON_LEFT, false)
			if VR.entering or VR.exiting or not VR.active:
				return
	else:
		for i in range(2):
			if not triggers[i] or _triggers[i] or not was_tracked[i]:
				continue
			if targets[i] == _switch:
				lights_on = not lights_on
				apply_lighting()
				break
			elif targets[i] == _screen.get_node("Hitbox"):
				_active_hand = i
				_move_mouse(positions[i])
				_pressed_hand = i
				_mouse_button(MOUSE_BUTTON_LEFT, true)
				if VR.entering or VR.exiting or not VR.active:
					return
				break

	if _pressed_hand < 0:
		if targets[_active_hand] != _screen.get_node("Hitbox"):
			_active_hand = 1 - _active_hand
		var over_tv: bool = targets[_active_hand] == _screen.get_node("Hitbox")
		if over_tv:
			_move_mouse(positions[_active_hand])
			var scroll := _hands[_active_hand].get_vector2("primary").y
			if absf(scroll) > 0.55 and _scroll_wait <= 0.0:
				var button := MOUSE_BUTTON_WHEEL_UP if scroll > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
				_mouse_button(button, true)
				_mouse_button(button, false)
				_scroll_wait = 0.12
		elif _mouse_over:
			_move_mouse(Vector2(-1000, -1000))
	_triggers = triggers


func _aim_pose(hand: XRController3D):
	var tracker := XRServer.get_tracker(hand.tracker) as XRPositionalTracker
	var aim := tracker.get_pose("aim") if tracker else null
	if aim and aim.has_tracking_data:
		return $XROrigin3D.global_transform * aim.get_adjusted_transform()
	var grip := tracker.get_pose(hand.pose) if tracker else null
	if grip and grip.has_tracking_data:
		return $XROrigin3D.global_transform * grip.get_adjusted_transform()
	return null


func _move_mouse(at: Vector2) -> void:
	_mouse_position = at
	_mouse_over = get_tree().root.get_visible_rect().has_point(at)
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed_hand >= 0 else 0
	get_tree().root.push_input(event, true)


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = _mouse_position
	event.global_position = _mouse_position
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	get_tree().root.push_input(event, true)


func reset_pointers() -> void:
	var was_pressed := _pressed_hand >= 0
	_pressed_hand = -1
	if was_pressed or _mouse_over:
		_move_mouse(Vector2(-1000, -1000))
	if was_pressed:
		_mouse_button(MOUSE_BUTTON_LEFT, false)
	for i in range(2):
		_hands[i].get_node("Pointer").hide()
		_triggers[i] = _hands[i].get_is_active() and _hands[i].get_float("trigger") > 0.65
		_tracked[i] = false
		_captured[i] = false
