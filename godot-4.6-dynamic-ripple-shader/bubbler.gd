extends Node3D

var _particles: GPUParticles3D

func _ready() -> void:
	_particles = $GPUParticles3D

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 8.0
	mat.direction             = Vector3(0, 1, 0)
	mat.spread                = 5.0
	mat.initial_velocity_min  = 0.3
	mat.initial_velocity_max  = 0.8
	mat.gravity               = Vector3.ZERO
	mat.scale_min             = 0.06
	mat.scale_max             = 0.18

	var grad     := Gradient.new()
	grad.colors   = PackedColorArray([Color(1,1,1,0), Color(1,1,1,0.7), Color(1,1,1,0)])
	grad.offsets  = PackedFloat32Array([0.0, 0.3, 1.0])
	var gtex     := GradientTexture1D.new()
	gtex.gradient = grad
	mat.color_ramp = gtex

	var mesh     := SphereMesh.new()
	mesh.radius   = 0.1
	mesh.height   = 0.2
	mesh.radial_segments = 6
	mesh.rings    = 3

	var mmat     := ShaderMaterial.new()
	mmat.shader          = load("res://bubble.gdshader")
	mmat.render_priority = 10
	mesh.material = mmat

	_particles.amount          = 200
	_particles.lifetime        = 4.0
	_particles.one_shot        = false
	_particles.explosiveness   = 0.0
	_particles.local_coords    = false
	_particles.emitting        = false
	_particles.visibility_aabb = AABB(Vector3(-12, -2, -12), Vector3(24, 10, 24))
	_particles.process_material = mat
	_particles.draw_pass_1     = mesh

func set_water_y(y: float) -> void:
	var m := _particles.draw_pass_1.surface_get_material(0) as ShaderMaterial
	if m:
		m.set_shader_parameter("water_y", y)

func set_active(on: bool) -> void:
	_particles.emitting = on

func set_rate(ratio: float) -> void:
	_particles.amount_ratio = clamp(ratio, 0.0, 1.0)

func set_alpha(val: float) -> void:
	var m := _particles.draw_pass_1.surface_get_material(0) as ShaderMaterial
	if m:
		m.set_shader_parameter("alpha_scale", val)
