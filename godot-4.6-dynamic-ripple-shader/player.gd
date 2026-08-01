extends RigidBody3D

@export var move_speed  : float = 6.0
@export var jump_force  : float = 6.0
@export var mouse_sens  : float = 0.003
@export var arm_length  : float = 3.0
@export var pitch_min   : float = -30.0
@export var pitch_max   : float = 60.0
@export var water_y     : float = 0.0
@export var wave_height : float = 2.5

var _yaw    : float = 0.0
var _pitch  : float = 20.0
var _on_floor : bool = false

@onready var _pivot : Node3D      = $CamPivot
@onready var _arm   : SpringArm3D = $CamPivot/SpringArm3D

var _underwater_mat : ShaderMaterial
var _cam : Camera3D
var _bubbler : Node3D

func _ready() -> void:
	lock_rotation = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# 2D CanvasLayer overlay
	_underwater_mat = ShaderMaterial.new()
	_underwater_mat.shader = load("res://underwater.gdshader")
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _underwater_mat
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	layer.add_child(rect)

	# Cache camera
	for c in _arm.get_children():
		if c is Camera3D:
			_cam = c
			break

	# Spawn bubbler and attach to player
	var BubblerScene := load("res://bubbler.tscn")
	_bubbler = BubblerScene.instantiate()
	add_child(_bubbler)

	# Auto-detect water Y
	for node in get_parent().get_children():
		if node is MeshInstance3D and node.get_script() != null:
			if "ocean" in node.get_script().resource_path.to_lower():
				water_y = node.global_position.y
				break
	_bubbler.set_water_y(water_y + wave_height)
	# Render after toon quad (priority 0) so halftone doesn't apply to player
	for child in get_children():
		if child is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.8, 0.8, 0.8, 1.0)
			m.render_priority = 3
			child.set_surface_override_material(0, m)
	if _arm:
		_arm.spring_length = arm_length

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_yaw   -= event.relative.x * mouse_sens
		_pitch  = clamp(_pitch - event.relative.y * mouse_sens * 57.3,
						pitch_min, pitch_max)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(_delta: float) -> void:
	_check_floor()

	# Camera look direction defines forward — use pivot's real world transform
	_pivot.rotation.y = _yaw
	_pivot.rotation.x = deg_to_rad(_pitch)
	var yaw_basis := Basis(Vector3.UP, _yaw)
	var forward   := -yaw_basis.z
	var right     :=  yaw_basis.x

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		dir += forward
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		dir -= forward
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		dir -= right
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		dir += right

	var vel       := linear_velocity
	var target_xz := dir.normalized() * move_speed if dir.length() > 0.1 else Vector3.ZERO
	vel.x = target_xz.x
	vel.z = target_xz.z
	linear_velocity = vel

	if _on_floor and (Input.is_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("ui_accept")):
		linear_velocity.y = jump_force

func _process(_delta: float) -> void:
	if _underwater_mat == null:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_y := cam.global_position.y if cam else global_position.y
	var under: float = clamp((water_y + wave_height - cam_y) / 0.25, 0.0, 1.0)
	_underwater_mat.set_shader_parameter("strength", under)
	if _bubbler:
		_bubbler.set_active(under > 0.05)
		_bubbler.set_alpha(under)
		var h_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
		var rate := lerpf(1.0, 0.15, clamp(h_speed / move_speed, 0.0, 1.0))
		_bubbler.set_rate(rate)

func _check_floor() -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * 1.1)
	query.exclude = [get_rid()]
	_on_floor = space.intersect_ray(query).size() > 0
