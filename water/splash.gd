extends Node3D

signal finished

@export var duration: float = 0.75
@export var autoplay: bool = false

var _mats: Array[ShaderMaterial] = []
var _sparkles: GPUParticles3D
var _land: GPUParticles3D
var _follow: Node3D = null

func _ready() -> void:
	visible = false
	_init_mats()
	_init_sparkles()
	_init_land()
	_set_elapsed(0.0)
	if autoplay:
		play()

func play() -> void:
	visible = true
	_set_elapsed(0.0)
	_sparkles.restart()

	var half := duration * 0.5
	var tween := create_tween()
	tween.tween_method(_set_elapsed, 0.0, 0.5, half)
	tween.tween_method(_set_elapsed, 0.5, 1.0, half * 1.25)

	var land_timer := create_tween()
	land_timer.tween_callback(_land.restart).set_delay(half + half * 1.25 * 0.44)

	await tween.finished
	visible = false
	finished.emit()

func _init_sparkles() -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape              = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis          = Vector3(0, 1, 0)
	mat.emission_ring_radius        = 1.4
	mat.emission_ring_inner_radius  = 0.9
	mat.emission_ring_height        = 0.05
	mat.direction              = Vector3(0, 1, 0)
	mat.spread                 = 45.0
	mat.initial_velocity_min   = 3.5
	mat.initial_velocity_max   = 6.5
	mat.gravity                = Vector3(0, -9.5, 0)
	mat.scale_min              = 0.02
	mat.scale_max              = 0.10
	mat.angular_velocity_min   = -200.0
	mat.angular_velocity_max   =  200.0

	var grad := Gradient.new()
	grad.colors  = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.4, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	var mesh      := SphereMesh.new()
	mesh.radius    = 0.18
	mesh.height    = 0.72
	mesh.radial_segments = 10
	mesh.rings     = 5

	var mmat := ShaderMaterial.new()
	mmat.shader          = load("res://water/bubble.gdshader")
	mmat.render_priority = 2
	mesh.material = mmat

	_sparkles = GPUParticles3D.new()
	_sparkles.amount          = 35
	_sparkles.lifetime        = duration * 1.1
	_sparkles.one_shot        = true
	_sparkles.explosiveness   = 0.55
	_sparkles.emitting        = false
	_sparkles.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 12, 10))
	_sparkles.process_material = mat
	_sparkles.draw_pass_1     = mesh
	add_child(_sparkles)

func _init_land() -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape             = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis         = Vector3(0, 1, 0)
	mat.emission_ring_radius       = 1.3
	mat.emission_ring_inner_radius = 0.8
	mat.emission_ring_height       = 0.05
	# spread outward and low like water hitting a flat surface
	mat.direction             = Vector3(0, 0.3, 0)
	mat.spread                = 80.0
	mat.flatness              = 0.85
	mat.initial_velocity_min  = 1.5
	mat.initial_velocity_max  = 4.0
	mat.gravity               = Vector3(0, -6.0, 0)
	mat.scale_min             = 0.03
	mat.scale_max             = 0.1

	var grad := Gradient.new()
	grad.colors  = PackedColorArray([Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	var mesh     := SphereMesh.new()
	mesh.radius   = 0.08
	mesh.height   = 0.22
	mesh.radial_segments = 6
	mesh.rings    = 3
	var mmat     := ShaderMaterial.new()
	mmat.shader          = load("res://water/bubble.gdshader")
	mmat.render_priority = 2
	mesh.material = mmat

	_land = GPUParticles3D.new()
	_land.amount          = 25
	_land.lifetime        = 0.5
	_land.one_shot        = true
	_land.explosiveness   = 0.85
	_land.emitting        = false
	_land.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 6, 12))
	_land.process_material = mat
	_land.draw_pass_1     = mesh
	add_child(_land)

func _init_mats() -> void:
	_mats.clear()
	var priority := 2
	for child in get_children():
		if not child is MeshInstance3D:
			continue
		var mat := child.get_surface_override_material(0) as ShaderMaterial
		if mat == null:
			continue
		# duplicate so each mesh gets its own instance with a unique render_priority this is
		var copy := mat.duplicate() as ShaderMaterial
		copy.render_priority = priority
		priority += 1
		child.set_surface_override_material(0, copy)
		_mats.append(copy)

func _process(delta: float) -> void:
	if _follow and is_instance_valid(_follow) and visible:
		global_position.x = lerp(global_position.x, _follow.global_position.x, delta * 5.0)
		global_position.z = lerp(global_position.z, _follow.global_position.z, delta * 5.0)

func _set_elapsed(t: float) -> void:
	for mat in _mats:
		mat.set_shader_parameter("elapsed", t)
