extends Node

signal mode_changed

const DEVICE := 15
var active := false
var quest_standalone := false
var room_view: SubViewport
var _interface: XRInterface
var _hands: Array[XRController3D] = []
var _buttons: Dictionary = {}
var _axes: Dictionary = {}
var _actions: Dictionary = {}


func _ready() -> void:
	_interface = XRServer.find_interface("OpenXR")
	var info := str(_interface.get_system_info()) if _interface and _interface.is_initialized() else ""
	quest_standalone = is_standalone_quest(OS.get_name(), OS.get_model_name(), info, OS.has_feature("quest"))
	if "--vr-preview" in OS.get_cmdline_user_args():
		call_deferred("start", true)
	elif _interface and _interface.is_initialized():
		call_deferred("start")


static func is_standalone_quest(platform: String, model: String, runtime: String, quest_export := false) -> bool:
	if platform != "Android":
		return false
	var identity := (model + " " + runtime).to_lower()
	return quest_export or "quest" in identity or "oculus" in identity or "meta" in identity


func start(preview := false) -> bool:
	if active:
		return true
	if not preview and (_interface == null or (not _interface.is_initialized() and not _interface.initialize())):
		return false
	if not preview:
		_interface.interface_is_primary = true
		quest_standalone = is_standalone_quest(OS.get_name(), OS.get_model_name(), str(_interface.get_system_info()), OS.has_feature("quest"))
	room_view = SubViewport.new()
	room_view.name = "VRRoomView"
	room_view.own_world_3d = true
	room_view.size = Vector2i(1280, 720)
	room_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	room_view.use_xr = not preview
	add_child(room_view)
	var room: Node3D = load("res://water/vr_room.tscn").instantiate()
	room.scale = Vector3.ONE * 3.0
	room_view.add_child(room)
	var screen := MeshInstance3D.new()
	screen.name = "GameScreen"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.684, 0.385)
	screen.mesh = quad
	screen.position = Vector3(-0.02897, 0.4101, -0.359)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = get_tree().root.get_texture()
	screen.material_override = material
	room.add_child(screen)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.09, 0.1)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	room_view.add_child(environment)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.1, 0)
	light.omni_range = 8
	room_view.add_child(light)
	var origin := XROrigin3D.new()
	origin.position = Vector3(0, 0, 1.8)
	room_view.add_child(origin)
	var camera: Camera3D = Camera3D.new() if preview else XRCamera3D.new()
	origin.add_child(camera)
	camera.current = true
	if preview:
		camera.position.y = 1.6
		camera.look_at(Vector3(-0.087, 1.23, -1.1))
	else:
		for hand in ["left_hand", "right_hand"]:
			var controller := XRController3D.new()
			controller.tracker = hand
			origin.add_child(controller)
			_hands.append(controller)
	active = true
	mode_changed.emit()
	return true


func stop() -> void:
	for action in _actions.keys():
		_action(action, false)
	for button in _buttons.keys():
		_button(button, false)
	for axis in _axes.keys():
		_axis(axis, 0.0)
	_hands.clear()
	if is_instance_valid(room_view):
		room_view.use_xr = false
		room_view.queue_free()
	active = false
	mode_changed.emit()


func _process(_delta: float) -> void:
	if not active or _hands.size() != 2:
		return
	var menus := not ControllerNavigation._controls().is_empty()
	for i in range(2):
		var hand := _hands[i]
		var tracked := hand.get_is_active()
		var stick := hand.get_vector2("primary") if tracked else Vector2.ZERO
		_axis(i * 2, stick.x)
		_axis(i * 2 + 1, -stick.y)
		var ax := tracked and hand.is_button_pressed("ax_button")
		var by := tracked and hand.is_button_pressed("by_button")
		_button(JOY_BUTTON_A if i == 1 else JOY_BUTTON_X, ax if menus else false)
		_button(JOY_BUTTON_B if i == 1 else JOY_BUTTON_Y, by if menus else false)
		_action("jump" if i == 1 else "water_attack", ax and not menus)
		_action("water_power" if i == 1 else "water_wall", by and not menus)
		_action("revive" if i == 1 else "swim_key", tracked and hand.is_button_pressed("primary_click") and not menus)
		_action("vr_dodge_right" if i == 1 else "vr_dodge_left", tracked and hand.get_float("grip") > 0.65 and not menus)
		var trigger := tracked and hand.get_float("trigger") > 0.65 and not menus
		var arcade := Net.game_mode == Net.GameMode.ARCADE
		_action("arcade_e" if i == 1 else "arcade_q", trigger and arcade)
		_action("water_pelt" if i == 1 else "water_counter", trigger and not arcade)
	_action("ui_cancel", _hands[0].get_is_active() and _hands[0].is_button_pressed("menu_button"))


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
