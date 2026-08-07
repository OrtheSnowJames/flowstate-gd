## FluidBox — drop-in interactive 3D water volume for Godot 4 (4.2+, Forward+).
##
## The node origin sits AT the water surface; the volume extends `size.y`
## metres downward. Everything (mesh, sim viewports, collision area, splash
## particles) is built in _ready(), so usage is just:
##
##     var water := FluidBox.new()
##     water.size = Vector3(10, 2, 7)
##     add_child(water)
##     water.global_position = Vector3(0, 1.8, 0)   # y = surface height
##
## RigidBody3D / CharacterBody3D nodes that overlap the volume automatically
## produce entry splashes, wakes and bow waves scaled by mass × velocity.
##
## Gameplay API (for "pool fighting"):
##     add_impulse(world_pos, strength_m, radius_m, dir, dipole, elongation)
##     splash_at(world_pos, power, radius_m)
##     get_height_at(world_pos)          # needs enable_height_queries = true
##     signal body_splashed(body, power)
class_name FluidBox
extends Area3D

signal body_splashed(body: Node3D, power: float)

@export_group("Volume")
## Water volume in metres. X/Z = surface extent, Y = depth below the surface.
@export var size := Vector3(10.0, 2.0, 10.0)

@export_group("Simulation")
## Sim cells along the longest surface axis. 192–320 is a good range.
@export_range(64, 512) var sim_resolution := 256
## Wave propagation speed factor (0..0.5). Higher = faster waves. >0.5 unstable.
@export_range(0.05, 0.5) var wave_transfer := 0.30
## Energy retained per sim step. 1.0 = waves never die.
@export_range(0.9, 1.0) var wave_damping := 0.996
## Softens reflections off pool walls (0 = perfect mirror walls).
@export_range(0.0, 1.0) var edge_damping := 0.35

@export_group("Surface Look")
## Height in metres of a full-strength sim value. Bigger = taller waves.
@export_range(0.0, 2.0) var amplitude := 0.35
@export_range(60, 300) var mesh_resolution := 160
@export var surface_material_override: ShaderMaterial

@export_group("Body Interaction")
## Bodies slower than this on entry don't get a particle splash.
@export var min_splash_speed := 1.2
## Global multiplier for how deep a falling body dents the water.
@export var splash_strength := 1.0
## Multiplier for the bow wave / wake of bodies moving horizontally.
@export var wake_strength := 1.0
## Horizontal speed below which no wake is produced.
@export var wake_min_speed := 0.35
## Mass assumed for bodies without a `mass` property (CharacterBody3D etc).
@export var default_mass := 70.0

@export_group("Height Queries")
## Enables get_height_at() via async-ish GPU readback. Costs ~0.3–1 ms every
## `readback_interval` frames — leave off unless gameplay needs wave heights.
@export var enable_height_queries := false
@export_range(1, 30) var readback_interval := 4

const _SIM_SHADER := preload("res://poolk/water_sim.gdshader")
const _SURF_SHADER := preload("res://poolk/water_surface.gdshader")
const MAX_IMPULSES := 16
const SPLASH_POOL_SIZE := 10

var _vp_a: SubViewport
var _vp_b: SubViewport
var _mat_a: ShaderMaterial
var _mat_b: ShaderMaterial
var _surf_mat: ShaderMaterial
var _mesh: MeshInstance3D
var _flip := false
var _reset_frames := 3
var _sim_size := Vector2i(256, 256)

var _pending: Array[Dictionary] = []          # impulses queued this frame
var _tracked: Dictionary = {}                  # instance_id -> body state
var _splash_pool: Array[GPUParticles3D] = []
var _splash_idx := 0
var _readback_img: Image
var _readback_countdown := 0


func _ready() -> void:
	monitoring = true
	_build_collision()
	_build_sim()
	_build_surface()
	_build_splash_pool()


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------
func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0.0, -size.y * 0.5, 0.0)  # volume hangs below surface
	add_child(cs)


func _build_sim() -> void:
	# Cells are square in world space: scale the shorter axis of the texture.
	var aspect := size.z / size.x
	if aspect <= 1.0:
		_sim_size = Vector2i(sim_resolution, maxi(int(sim_resolution * aspect), 16))
	else:
		_sim_size = Vector2i(maxi(int(sim_resolution / aspect), 16), sim_resolution)

	_vp_a = _make_sim_viewport()
	_vp_b = _make_sim_viewport()
	_mat_a = (_vp_a.get_child(0) as ColorRect).material
	_mat_b = (_vp_b.get_child(0) as ColorRect).material
	# Static ping-pong wiring: A reads B, B reads A.
	_mat_a.set_shader_parameter("prev_tex", _vp_b.get_texture())
	_mat_b.set_shader_parameter("prev_tex", _vp_a.get_texture())


func _make_sim_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = _sim_size
	vp.disable_3d = true
	vp.use_hdr_2d = true                     # RGBA16F — precision + signed range
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.position = Vector2.ZERO
	rect.size = Vector2(_sim_size)
	var m := ShaderMaterial.new()
	m.shader = _SIM_SHADER
	m.set_shader_parameter("texel", Vector2(1.0 / _sim_size.x, 1.0 / _sim_size.y))
	m.set_shader_parameter("world_size", Vector2(size.x, size.z))
	m.set_shader_parameter("transfer", clampf(wave_transfer, 0.02, 0.5))
	m.set_shader_parameter("damping", wave_damping)
	m.set_shader_parameter("edge_damping", edge_damping)
	m.set_shader_parameter("reset", true)
	rect.material = m
	vp.add_child(rect)
	add_child(vp)
	return vp


func _build_surface() -> void:
	_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	var aspect := size.z / size.x
	plane.subdivide_width = mesh_resolution
	plane.subdivide_depth = maxi(int(mesh_resolution * aspect), 8)
	_mesh.mesh = plane

	if surface_material_override:
		_surf_mat = surface_material_override
	else:
		_surf_mat = ShaderMaterial.new()
		_surf_mat.shader = _SURF_SHADER
	_surf_mat.set_shader_parameter("texel", Vector2(1.0 / _sim_size.x, 1.0 / _sim_size.y))
	_surf_mat.set_shader_parameter("world_size", Vector2(size.x, size.z))
	_surf_mat.set_shader_parameter("amplitude", amplitude)
	_surf_mat.set_shader_parameter("height_tex", _vp_a.get_texture())
	_mesh.material_override = _surf_mat
	# Displaced verts can leave the flat AABB — pad it so waves never get culled.
	_mesh.custom_aabb = AABB(
		Vector3(-size.x * 0.5, -amplitude * 1.5, -size.z * 0.5),
		Vector3(size.x, amplitude * 3.0, size.z))
	add_child(_mesh)


func _build_splash_pool() -> void:
	for i in SPLASH_POOL_SIZE:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 1.0
		p.amount = 110
		p.lifetime = 0.85
		p.local_coords = false
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 26.0
		pm.gravity = Vector3(0.0, -24.0, 0.0)
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 6.0
		pm.damping_min = 0.4
		pm.damping_max = 1.6
		pm.scale_min = 0.35
		pm.scale_max = 1.0
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.25
		p.process_material = pm
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.10
		sphere.radial_segments = 8
		sphere.rings = 4
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.82, 0.90, 0.97, 0.85)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.roughness = 0.06
		sm.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		sphere.material = sm
		p.draw_pass_1 = sphere
		add_child(p)
		_splash_pool.append(p)


# ---------------------------------------------------------------------------
# Per-frame: run the sim (render cadence) & interact with bodies (physics)
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	_flip = not _flip
	var dst_mat := _mat_a if _flip else _mat_b
	var dst_vp := _vp_a if _flip else _vp_b

	if _reset_frames > 0:
		_reset_frames -= 1
		dst_mat.set_shader_parameter("reset", true)
	else:
		dst_mat.set_shader_parameter("reset", false)

	_flush_impulses(dst_mat)
	dst_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_surf_mat.set_shader_parameter("height_tex", dst_vp.get_texture())

	if enable_height_queries:
		_readback_countdown -= 1
		if _readback_countdown <= 0:
			_readback_countdown = readback_interval
			_readback_img = dst_vp.get_texture().get_image()


func _flush_impulses(mat: ShaderMaterial) -> void:
	if _pending.size() > MAX_IMPULSES:
		_pending.sort_custom(func(a, b): return absf(a.s) > absf(b.s))
		_pending.resize(MAX_IMPULSES)
	var data: Array[Vector4] = []
	var dirs: Array[Vector4] = []
	for imp in _pending:
		data.append(Vector4(imp.p.x, imp.p.y, imp.r, imp.s))
		dirs.append(Vector4(imp.d.x, imp.d.y, imp.e, imp.dip))
	var n := data.size()
	while data.size() < MAX_IMPULSES:
		data.append(Vector4.ZERO)
		dirs.append(Vector4(1, 0, 0, 0))
	mat.set_shader_parameter("impulse_count", n)
	mat.set_shader_parameter("impulses", data)
	mat.set_shader_parameter("impulse_dirs", dirs)
	_pending.clear()


func _physics_process(delta: float) -> void:
	var seen := {}
	for body in get_overlapping_bodies():
		if not (body is RigidBody3D or body is CharacterBody3D):
			continue
		var id := body.get_instance_id()
		seen[id] = true
		var vel := _body_velocity(body)
		var radius := _body_radius(body)
		var mass := _body_mass(body)
		var pos := body.global_position

		if not _tracked.has(id):
			_tracked[id] = {"body": body, "pos": pos, "r": radius}
			_on_body_enter(body, vel, mass, radius)
		else:
			_tracked[id].pos = pos
		_continuous_interaction(body, vel, mass, radius, delta)

	# Exit splashes (body left or was freed).
	for id in _tracked.keys():
		if not seen.has(id):
			var st: Dictionary = _tracked[id]
			var b = st.body
			if is_instance_valid(b):
				var vel := _body_velocity(b)
				if vel.y > min_splash_speed:  # jumped OUT of the water
					var p: float = _body_mass(b) * vel.length()
					add_impulse(st.pos, 0.35 * splash_strength * clampf(p * 0.002, 0.02, 0.25), st.r * 1.3)
					_spawn_splash(_surface_point(st.pos), p * 0.5, st.r)
			_tracked.erase(id)


func _on_body_enter(body: Node3D, vel: Vector3, mass: float, radius: float) -> void:
	var speed := vel.length()
	if speed < 0.05:
		return
	# Momentum drives everything: p = m·v. sqrt keeps heavy/fast bodies from
	# instantly saturating the sim while still feeling much bigger.
	var momentum := mass * speed
	var strength := -splash_strength * clampf(sqrt(momentum) * 0.032, 0.03, 0.45)
	var r := radius * 1.25 + clampf(speed * 0.03, 0.0, 0.4)
	add_impulse(body.global_position, strength, r)

	if speed >= min_splash_speed:
		_spawn_splash(_surface_point(body.global_position), momentum, radius)
		body_splashed.emit(body, momentum)


func _continuous_interaction(body: Node3D, vel: Vector3, mass: float, radius: float, delta: float) -> void:
	var local := to_local(body.global_position)
	# Only bodies near the surface disturb it (deep swimmers don't).
	var depth_factor := clampf(1.0 + local.y / maxf(radius * 2.0, 0.3), 0.0, 1.0)
	if depth_factor <= 0.0:
		return
	var mass_f := clampf(sqrt(mass / default_mass), 0.35, 2.5)

	# --- Bow wave / wake from horizontal motion -----------------------------
	var hvel := Vector3(vel.x, 0.0, vel.z)
	var hspeed := hvel.length()
	if hspeed > wake_min_speed:
		var dir := hvel / hspeed
		var ahead := body.global_position + dir * radius * 0.7
		# Dipole travelling in `dir`: crest pushed forward, trough dragged behind
		# — a real bow wave that keeps propagating after the body slows. The
		# per-frame crest scales with how fast the body moves (Froude-like):
		# `speed_amt` ramps 0->1 across a realistic swim/push range, so a slow
		# drift barely ripples while a fast shove throws a clear mini bow wave.
		# It's velocity-based with no constant floor, and framerate-independent
		# because it's multiplied by delta.
		var speed_amt := clampf(hspeed / 5.0, 0.0, 1.0)
		var push := wake_strength * mass_f * speed_amt * delta * 7.0
		# elongation stretches the crest into a forward FRONT the faster it goes.
		add_impulse(ahead, push, radius * 1.2, dir, 1.0, clampf(hspeed * 0.32, 0.0, 3.5))
		# Plus the hole the hull carves (depression at the body).
		add_impulse(body.global_position, -push * 0.55 * depth_factor, radius)

	# --- Vertical bobbing near the surface ----------------------------------
	if absf(vel.y) > 0.25 and depth_factor > 0.05:
		var s := clampf(-vel.y * delta * 0.9, -0.06, 0.06) * mass_f * depth_factor
		add_impulse(body.global_position, s * splash_strength, radius * 1.1)


# ---------------------------------------------------------------------------
# Public gameplay API
# ---------------------------------------------------------------------------
## Inject a disturbance. strength_m: signed metres (negative = press water down,
## positive = raise it). dir + dipole=1.0 makes a travelling wave (attack push);
## elongation stretches it along dir.
func add_impulse(world_pos: Vector3, strength_m: float, radius_m: float,
		dir: Vector3 = Vector3.ZERO, dipole := 0.0, elongation := 0.0) -> void:
	var local := to_local(world_pos)
	var m := Vector2(local.x + size.x * 0.5, local.z + size.z * 0.5)
	var margin := radius_m * 3.0
	if m.x < -margin or m.y < -margin or m.x > size.x + margin or m.y > size.z + margin:
		return
	var d2 := Vector2(dir.x, dir.z)
	d2 = d2.normalized() if d2.length_squared() > 0.0001 else Vector2.RIGHT
	_pending.append({
		"p": m, "r": maxf(radius_m, 0.02), "s": strength_m,
		"d": d2, "e": maxf(elongation, 0.0), "dip": clampf(dipole, 0.0, 1.0),
	})


## Cosmetic splash + ripple at a point (e.g. a bullet hit or a spell).
## power ≈ mass · speed of the equivalent impact.
func splash_at(world_pos: Vector3, power: float, radius_m := 0.3) -> void:
	add_impulse(world_pos, -clampf(sqrt(maxf(power, 0.0)) * 0.03, 0.02, 0.4), radius_m)
	_spawn_splash(_surface_point(world_pos), power, radius_m)


## Wave height above the rest surface, in metres. Requires
## enable_height_queries = true; otherwise returns 0.
func get_height_at(world_pos: Vector3) -> float:
	if _readback_img == null:
		return 0.0
	var local := to_local(world_pos)
	var u := clampf(local.x / size.x + 0.5, 0.0, 1.0)
	var v := clampf(local.z / size.z + 0.5, 0.0, 1.0)
	var px := mini(int(u * (_sim_size.x - 1)), _sim_size.x - 1)
	var py := mini(int(v * (_sim_size.y - 1)), _sim_size.y - 1)
	return (_readback_img.get_pixel(px, py).r - 0.5) * amplitude


## World-space position of the rest surface directly above/below `world_pos`.
func _surface_point(world_pos: Vector3) -> Vector3:
	var local := to_local(world_pos)
	local.y = 0.0
	return to_global(local)


# ---------------------------------------------------------------------------
# Splash particles — amount, size and speed scale with momentum (mass × speed)
# ---------------------------------------------------------------------------
func _spawn_splash(pos: Vector3, momentum: float, radius: float) -> void:
	var p := _splash_pool[_splash_idx]
	_splash_idx = (_splash_idx + 1) % _splash_pool.size()
	var t := clampf(momentum / 300.0, 0.0, 1.0)   # 0 = pebble, 1 = ~anvil at speed
	var pm: ParticleProcessMaterial = p.process_material
	pm.initial_velocity_min = lerpf(1.8, 6.5, t)
	pm.initial_velocity_max = lerpf(3.5, 12.0, t)
	pm.scale_min = lerpf(0.25, 0.7, t)
	pm.scale_max = lerpf(0.6, 1.9, t)
	pm.emission_sphere_radius = maxf(radius * 0.8, 0.12)
	p.amount_ratio = clampf(0.2 + t * 0.8, 0.2, 1.0)
	p.lifetime = lerpf(0.55, 1.1, t)
	p.global_position = pos
	p.restart()


# ---------------------------------------------------------------------------
# Body helpers (robust across body types)
# ---------------------------------------------------------------------------
func _body_velocity(body: Node3D) -> Vector3:
	if body is RigidBody3D:
		return body.linear_velocity
	var v = body.get("velocity")
	return v if v is Vector3 else Vector3.ZERO


func _body_mass(body: Node3D) -> float:
	var m = body.get("mass")
	return m if (m is float and m > 0.0) else default_mass


func _body_radius(body: Node3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null:
			var s: Shape3D = child.shape
			if s is SphereShape3D:
				return s.radius
			if s is BoxShape3D:
				return (s.size.x + s.size.z) * 0.28
			if s is CapsuleShape3D or s is CylinderShape3D:
				return s.radius
	return 0.35
