## Demo: a pool you can fight in.
##   LMB          throw a light ball        (mass 2)
##   MMB          throw a heavy cannonball  (mass 45)
##   F            water push attack — sends a travelling wave from the cursor
##                in the camera's facing direction
##   RMB drag     orbit camera   ·   wheel: zoom
extends Node3D

const FluidBoxScript := preload("res://poolk/fluid_box.gd")

const POOL_W := 11.0
const POOL_L := 7.5
const WATER_DEPTH := 1.7
const WATER_Y := 1.7            # world height of the rest surface

var _water: FluidBox
var _cam: Camera3D
var _yaw := -0.6
var _pitch := -0.45
var _dist := 12.0
var _orbiting := false


func _ready() -> void:
	_build_environment()
	_build_pool()
	_build_water()
	_build_camera()
	_build_hud()


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.45, 0.72)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.85)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_pool() -> void:
	var tile := StandardMaterial3D.new()
	tile.albedo_color = Color(0.75, 0.79, 0.8)
	tile.roughness = 0.35
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.72, 0.75)  # light pool bottom shows depth tint
	floor_mat.roughness = 0.4

	_add_box(Vector3(POOL_W + 1.2, 0.4, POOL_L + 1.2), Vector3(0, -0.2, 0), floor_mat)  # bottom
	var wall_h := WATER_Y + 0.45
	var t := 0.6
	_add_box(Vector3(POOL_W + 2.0 * t, wall_h, t), Vector3(0, wall_h * 0.5, -(POOL_L * 0.5 + t * 0.5)), tile)
	_add_box(Vector3(POOL_W + 2.0 * t, wall_h, t), Vector3(0, wall_h * 0.5, POOL_L * 0.5 + t * 0.5), tile)
	_add_box(Vector3(t, wall_h, POOL_L), Vector3(-(POOL_W * 0.5 + t * 0.5), wall_h * 0.5, 0), tile)
	_add_box(Vector3(t, wall_h, POOL_L), Vector3(POOL_W * 0.5 + t * 0.5, wall_h * 0.5, 0), tile)


func _add_box(box_size: Vector3, pos: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)
	body.position = pos
	add_child(body)


func _build_water() -> void:
	_water = FluidBoxScript.new()
	_water.size = Vector3(POOL_W, WATER_DEPTH, POOL_L)
	_water.sim_resolution = 288
	_water.amplitude = 0.32
	add_child(_water)
	_water.position = Vector3(0, WATER_Y, 0)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 65.0
	add_child(_cam)
	_update_camera()


func _update_camera() -> void:
	var target := Vector3(0, WATER_Y, 0)
	var basis := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	_cam.global_position = target + basis * Vector3(0, 0, _dist)
	_cam.look_at(target)


func _build_hud() -> void:
	var label := Label.new()
	label.text = "LMB: throw ball   MMB: heavy cannonball   F: water push attack   RMB drag: orbit   wheel: zoom"
	label.position = Vector2(12, 10)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 1)
	var ui := CanvasLayer.new()
	ui.add_child(label)
	add_child(ui)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_throw(2.0, 0.22, Color(0.9, 0.45, 0.2), 14.0)
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					_throw(45.0, 0.38, Color(0.25, 0.25, 0.28), 17.0)
			MOUSE_BUTTON_RIGHT:
				_orbiting = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_dist = clampf(_dist - 0.8, 4.0, 30.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = clampf(_dist + 0.8, 4.0, 30.0)
				_update_camera()
	elif event is InputEventMouseMotion and _orbiting:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch - event.relative.y * 0.006, -1.35, -0.08)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_water_push_attack()


func _mouse_ray() -> Array:
	var mp := get_viewport().get_mouse_position()
	return [_cam.project_ray_origin(mp), _cam.project_ray_normal(mp)]


func _throw(mass: float, radius: float, color: Color, speed: float) -> void:
	var ray := _mouse_ray()
	var body := RigidBody3D.new()
	body.mass = mass
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)
	add_child(body)
	body.global_position = ray[0] + ray[1] * 1.5
	body.linear_velocity = ray[1] * speed
	# tidy up bodies that fly out of the arena
	get_tree().create_timer(20.0).timeout.connect(func():
		if is_instance_valid(body):
			body.queue_free())


func _water_push_attack() -> void:
	# Intersect the mouse ray with the rest-surface plane, then shove a
	# travelling dipole wave in the camera's horizontal facing direction.
	var ray := _mouse_ray()
	var plane := Plane(Vector3.UP, WATER_Y)
	var hit = plane.intersects_ray(ray[0], ray[1])
	if hit == null:
		return
	var fwd := -_cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# dipole = 1 -> a directed wave that keeps travelling; elongation widens
	# it into a front instead of a dot.
	_water.add_impulse(hit, 0.30, 0.55, fwd, 1.0, 2.2)
	# a bit of spray at the origin sells the effort
	_water.splash_at(hit, 60.0, 0.4)
