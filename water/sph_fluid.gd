# gpu sph fluid a real particle based fluid simulation runs the sph glsl compute
extends MultiMeshInstance3D

@export_group("Simulation")
@export var particle_count: int = 2048
# local space box the fluid is confined to centred on this node
@export var bounds_size: Vector3 = Vector3(6.0, 5.0, 6.0)
@export var smoothing_radius: float = 0.5
@export var rest_density: float = 30.0
@export var stiffness: float = 60.0
@export var viscosity: float = 0.6
@export var particle_mass: float = 1.0
@export var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
# physics substeps per frame more more stable and more gpu work
@export_range(1, 8) var substeps: int = 2

@export_group("Rendering")
@export var particle_visual_radius: float = 0.16
@export var particle_color: Color = Color(0.25, 0.55, 0.85, 1.0)

@export_group("Interaction")
# a body player the fluid is pushed away from optional
@export var player_path: NodePath
# collision radius of that body in metres
@export var player_radius: float = 1.2

const _FLOATS_PER_PARTICLE := 12 # 3 vec4
const _PARAMS_FLOATS := 24 # matches params in sph glsl 96 bytes
const _LOCAL_GROUP := 64

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _particle_buf: RID
var _params_buf: RID
var _uniform_set: RID
var _groups: int

var _player: Node3D
var _mm_buffer: PackedFloat32Array # reused each frame for multimesh
var _ok := false


func _ready() -> void:
	if player_path:
		_player = get_node_or_null(player_path)
	if not _init_gpu():
		push_error("SPHFluid: GPU init failed — falling back to nothing. Check the console for shader errors.")
		return
	_init_multimesh()
	_ok = true


func _exit_tree() -> void:
	# a local renderingdevice owns its resources free them explicitly
	if _rd == null:
		return
	for rid in [_uniform_set, _pipeline, _params_buf, _particle_buf, _shader]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_rd.free()
	_rd = null


# gpu setup
func _init_gpu() -> bool:
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		push_error("SPHFluid: no local RenderingDevice (compute unsupported on this driver).")
		return false

	var shader_file: RDShaderFile = load("res://water/sph.glsl")
	if shader_file == null:
		push_error("SPHFluid: could not load sph.glsl.")
		return false
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	var err := spirv.compile_error_compute
	if err != "":
		push_error("SPHFluid: compute shader compile error:\n" + err)
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		push_error("SPHFluid: shader_create_from_spirv failed.")
		return false
	_pipeline = _rd.compute_pipeline_create(_shader)

	# particle storage buffer seeded with a dam break block
	var seed := _make_initial_particles()
	var pbytes := seed.to_byte_array()
	_particle_buf = _rd.storage_buffer_create(pbytes.size(), pbytes)

	# params storage buffer
	var params := PackedFloat32Array()
	params.resize(_PARAMS_FLOATS)
	var qbytes := params.to_byte_array()
	_params_buf = _rd.storage_buffer_create(qbytes.size(), qbytes)

	# uniform set
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u0.binding = 0
	u0.add_id(_particle_buf)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(_params_buf)
	_uniform_set = _rd.uniform_set_create([u0, u1], _shader, 0)

	_groups = int(ceil(float(particle_count) / float(_LOCAL_GROUP)))
	return true


# lay the particles out as a block filling one side of the box so
func _make_initial_particles() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(particle_count * _FLOATS_PER_PARTICLE)
	var spacing := smoothing_radius * 0.55
	# column dimensions a tall ish block against the x wall
	var half := bounds_size * 0.5
	var cols_x: int = max(int((bounds_size.x * 0.45) / spacing), 1)
	var cols_z: int = max(int((bounds_size.z * 0.9) / spacing), 1)
	for i in particle_count:
		var ix: int = i % cols_x
		var iz: int = (i / cols_x) % cols_z
		var iy: int = i / (cols_x * cols_z)
		var base: int = i * _FLOATS_PER_PARTICLE
		arr[base + 0] = -half.x + 0.3 + float(ix) * spacing
		arr[base + 1] = -half.y + 0.3 + float(iy) * spacing
		arr[base + 2] = -half.z * 0.9 + float(iz) * spacing
		# vel 4 7 and aux 8 11 stay zero
	return arr


func _init_multimesh() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = particle_visual_radius
	mesh.height = particle_visual_radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = particle_color
	mat.roughness = 0.15
	mat.metallic = 0.0
	mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = particle_count
	multimesh = mm

	_mm_buffer = PackedFloat32Array()
	_mm_buffer.resize(particle_count * 12)


# per frame step the sim and push positions to the multimesh
func _physics_process(delta: float) -> void:
	if not _ok:
		return
	# clamp the frame time so a hitch cant blow the integrator up
	var frame_dt := clampf(delta, 0.0, 1.0 / 30.0)
	var sub_dt := frame_dt / float(substeps)

	var player_local := Vector4.ZERO
	if _player and is_instance_valid(_player):
		var lp := to_local(_player.global_position)
		player_local = Vector4(lp.x, lp.y, lp.z, player_radius)

	for _s in substeps:
		_write_params(sub_dt, player_local)
		_dispatch()

	_read_back_to_multimesh()


func _write_params(dt: float, player_local: Vector4) -> void:
	var half := bounds_size * 0.5
	var p := PackedFloat32Array()
	p.resize(_PARAMS_FLOATS)
	p[0] = dt
	p[1] = float(particle_count)
	p[2] = smoothing_radius
	p[3] = rest_density
	p[4] = stiffness
	p[5] = viscosity
	p[6] = particle_mass
	p[7] = 0.0
	p[8] = gravity.x;  p[9] = gravity.y;  p[10] = gravity.z; p[11] = 0.0
	p[12] = -half.x;   p[13] = -half.y;   p[14] = -half.z;   p[15] = 0.0
	p[16] = half.x;    p[17] = half.y;    p[18] = half.z;    p[19] = 0.0
	p[20] = player_local.x; p[21] = player_local.y; p[22] = player_local.z; p[23] = player_local.w
	_rd.buffer_update(_params_buf, 0, p.size() * 4, p.to_byte_array())


func _dispatch() -> void:
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	# stage 0 density pressure
	_rd.compute_list_set_push_constant(cl, _stage_bytes(0), 16)
	_rd.compute_list_dispatch(cl, _groups, 1, 1)
	_rd.compute_list_add_barrier(cl)
	# stage 1 forces integrate
	_rd.compute_list_set_push_constant(cl, _stage_bytes(1), 16)
	_rd.compute_list_dispatch(cl, _groups, 1, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()


func _stage_bytes(stage: int) -> PackedByteArray:
	var a := PackedInt32Array([stage, 0, 0, 0]) # 16 bytes push constant aligned
	return a.to_byte_array()


func _read_back_to_multimesh() -> void:
	var bytes := _rd.buffer_get_data(_particle_buf)
	var f := bytes.to_float32_array()
	for i in particle_count:
		var b := i * _FLOATS_PER_PARTICLE
		var m := i * 12
		# identity basis translation row major 3 4
		_mm_buffer[m + 0] = 1.0; _mm_buffer[m + 1] = 0.0; _mm_buffer[m + 2] = 0.0;  _mm_buffer[m + 3]  = f[b + 0]
		_mm_buffer[m + 4] = 0.0; _mm_buffer[m + 5] = 1.0; _mm_buffer[m + 6] = 0.0;  _mm_buffer[m + 7]  = f[b + 1]
		_mm_buffer[m + 8] = 0.0; _mm_buffer[m + 9] = 0.0; _mm_buffer[m + 10] = 1.0; _mm_buffer[m + 11] = f[b + 2]
	multimesh.buffer = _mm_buffer
