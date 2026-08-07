extends MeshInstance3D

const SLOTS_PER_BODY : int   = 128
const MAX_BODIES     : int   = 1
const TRAIL_LEN      : int   = SLOTS_PER_BODY * MAX_BODIES
const MIN_MOVE_DIST  : float = 0.08

const SplashScene := preload("res://water/splash.tscn")
const DropletShader := preload("res://water/droplet.gdshader")
const WaveShader := preload("res://water/wave.gdshader")

var _mat     : ShaderMaterial
var _elapsed : float = 0.0
var _bodies  : Dictionary = {}

var _trail_pos    : PackedVector3Array
var _trail_age    : PackedFloat32Array
var _wake         : GPUParticles3D
var _bubbles      : GPUParticles3D

func _ready() -> void:
	var shader = load("res://water/water shader 2.gdshader") as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	# Copy saved parameter values from the .tres material so colors/waves stay intact
	var base := get_active_material(0) as ShaderMaterial
	if base:
		for param in base.shader.get_shader_uniform_list():
			var val = base.get_shader_parameter(param["name"])
			if val != null:
				_mat.set_shader_parameter(param["name"], val)
	_mat.render_priority = 1
	set_surface_override_material(0, _mat)

	_trail_pos = PackedVector3Array()
	_trail_age = PackedFloat32Array()
	for i in TRAIL_LEN:
		_trail_pos.append(Vector3(99999, 0, 99999))
		_trail_age.append(9999.0)

	_mat.set_shader_parameter("trail_pos",     _trail_pos)
	_mat.set_shader_parameter("trail_age",     _trail_age)
	_mat.set_shader_parameter("ripple_str",    0.4)
	_mat.set_shader_parameter("ripple_freq",   40.0)
	_mat.set_shader_parameter("ripple_speed",  4.0)
	# ripple_decay is per-second in the shader's exp(-age * ripple_decay), and
	# ripple_radius is a hard distance cutoff -- at the old 2.0/50.0 a ripple's
	# wavefront (age * ripple_speed) could travel several meters before fading,
	# reading as a splash's ring crossing the whole pool. Decay much faster in
	# time and clamp the distance tight so ripples die out locally instead.
	_mat.set_shader_parameter("ripple_radius", 12.0)
	_mat.set_shader_parameter("ripple_decay",  6.0)
	_mat.set_shader_parameter("player_radius", 1.2)
	_init_wake()
	_init_bubbles()

func _init_wake() -> void:
	var mat := ParticleProcessMaterial.new()
	# Use SPHERE not RING — guaranteed available in all Godot 4 versions
	mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 1.4
	mat.direction              = Vector3(0, 1, 0)
	mat.spread                 = 80.0
	mat.flatness               = 0.6
	mat.initial_velocity_min   = 0.5
	mat.initial_velocity_max   = 2.0
	mat.gravity                = Vector3(0, -9.5, 0)
	mat.scale_min              = 0.03
	mat.scale_max              = 0.09
	mat.angular_velocity_min  = -200.0
	mat.angular_velocity_max  =  200.0
	var grad     := Gradient.new()
	grad.colors   = PackedColorArray([Color(0.85, 0.97, 1.0, 0.5), Color(0.85, 0.97, 1.0, 0.0)])
	grad.offsets  = PackedFloat32Array([0.3, 1.0])
	var gtex     := GradientTexture1D.new()
	gtex.gradient = grad
	mat.color_ramp = gtex

	var wake_mesh     := SphereMesh.new()
	wake_mesh.radius   = 0.18
	wake_mesh.height   = 0.72
	wake_mesh.radial_segments = 10
	wake_mesh.rings    = 5
	var mmat     := ShaderMaterial.new()
	mmat.shader          = load("res://water/bubble.gdshader")
	mmat.render_priority = 2
	wake_mesh.material = mmat

	_wake = GPUParticles3D.new()
	_wake.amount          = 200
	_wake.lifetime        = 1.0
	_wake.one_shot        = false
	_wake.explosiveness   = 0.0
	_wake.local_coords    = false
	_wake.emitting        = false
	_wake.visibility_aabb = AABB(Vector3(-60, -2, -60), Vector3(120, 10, 120))
	_wake.process_material = mat
	_wake.draw_pass_1     = wake_mesh
	add_child(_wake)

func _init_bubbles() -> void:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents  = Vector3(120.0, 1.0, 120.0)
	mat.direction             = Vector3(0, 1, 0)
	mat.spread                = 8.0
	mat.initial_velocity_min  = 0.1
	mat.initial_velocity_max  = 0.4
	mat.gravity               = Vector3(0, 0, 0)
	mat.scale_min             = 0.3
	mat.scale_max             = 0.8

	var grad     := Gradient.new()
	grad.colors   = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	grad.offsets  = PackedFloat32Array([0.0, 0.4, 1.0])
	var gtex     := GradientTexture1D.new()
	gtex.gradient = grad
	mat.color_ramp = gtex

	var bubble_mesh     := SphereMesh.new()
	bubble_mesh.radius   = 0.08
	bubble_mesh.height   = 0.16
	bubble_mesh.radial_segments = 6
	bubble_mesh.rings    = 3
	var mmat     := ShaderMaterial.new()
	mmat.shader          = load("res://water/bubble.gdshader")
	mmat.render_priority = 2
	bubble_mesh.material = mmat

	_bubbles = GPUParticles3D.new()
	_bubbles.amount           = 2000
	_bubbles.lifetime         = 5.0
	_bubbles.one_shot         = false
	_bubbles.explosiveness    = 0.0
	_bubbles.local_coords     = true
	_bubbles.emitting         = true
	_bubbles.visibility_aabb  = AABB(Vector3(-130, -4, -130), Vector3(260, 8, 260))
	_bubbles.process_material = mat
	_bubbles.draw_pass_1      = bubble_mesh
	call_deferred("_add_bubbles")

## World-space height of the water surface at the given point. The surface is
## flat for buoyancy purposes, so x/z are ignored. The mesh's vertices are
## offset from the node origin (see its AABB), so add that offset to land on the
## actual visible surface rather than the node position.
func get_height_at(world_pos: Vector3) -> float:
	var box := get_aabb()
	var base := global_position.y + box.position.y + box.size.y * 0.5
	# Add the live swell height so buoyant bodies bob with the visible waves.
	return base + _wave_height(world_pos.x, world_pos.z)

## The undisturbed surface, with no swell on top. player.gd needs the baseline
## separately from get_height_at so it can bound how far a dip in the water is
## allowed to weaken buoyancy -- see its _water_height().
func get_rest_height() -> float:
	var box := get_aabb()
	return global_position.y + box.position.y + box.size.y * 0.5

## One directional wave. MUST stay identical to wave_term() in the water shader.
func _wave_term(p: Vector2, d: Vector2, wl: float, amp: float, sp: float) -> float:
	d = d.normalized()
	var w := TAU / wl
	var ph := w * d.dot(p) + _elapsed * sp * w
	return amp * sin(ph)

## World-space swell height at (x,z). The wave set here is identical to wave_h()
## in the shader, and both read _elapsed / wave_time, so the CPU height the player
## floats on exactly matches the surface you see.
func _wave_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := 0.0
	h += _wave_term(p, Vector2(1.0, 0.6), 6.0, 0.060, 1.2)
	h += _wave_term(p, Vector2(-0.7, 1.0), 3.5, 0.040, 1.5)
	h += _wave_term(p, Vector2(0.3, -1.0), 2.0, 0.025, 1.9)
	h += _wave_term(p, Vector2(1.0, 0.25), 1.2, 0.015, 2.4)
	var amp_scale := 1.0
	if _mat:
		var v = _mat.get_shader_parameter("wave_amp_scale")
		if v != null:
			amp_scale = v
	return h * amp_scale

## Spawn a big blue water eruption at `world_pos`: a tall central jet punching
## straight up plus a wide crown of droplets spraying outward, all arcing back
## down under gravity. `strength` (~0.5 to 2.5) scales count, height and size.
## Call whenever something breaks the surface. Frees itself when it finishes.
func splash_at(world_pos: Vector3, strength: float = 1.0) -> void:
	strength = clampf(strength, 0.2, 4.0)

	var root := Node3D.new()
	get_parent().add_child(root)
	root.global_position = world_pos

	# Central jet: a tight column of small droplets that shoots up.
	var jet := _make_droplet_burst(
		int(clampf(34.0 * strength, 12, 180)),  # amount (unchanged)
		0.10,                                    # emission radius (tight)
		14.0,                                    # spread degrees (narrow column)
		4.5 * strength, 6.5 * strength,          # velocity min/max (calmer)
		0.03, 0.09,                              # droplet scale min/max (small)
		1.2)                                     # lifetime (up and back down)

	# Crown: a fan of fine droplets spraying out sideways.
	var crown := _make_droplet_burst(
		int(clampf(70.0 * strength, 20, 320)),
		0.20 * strength,
		62.0,
		2.5 * strength, 4.5 * strength,
		0.015, 0.05,
		0.85)

	root.add_child(jet)
	root.add_child(crown)
	jet.emitting = true
	crown.emitting = true
	# The jet lives longest, so freeing on its finish clears the whole burst.
	jet.finished.connect(root.queue_free)

## Fire a fast, tight cone of water forward from `origin` along `direction` --
## the visual for a "water push" attack. Only lightly pulled down so it reads as
## a forward shove of water rather than a fountain. Frees itself when done.
func water_blast(origin: Vector3, direction: Vector3, strength: float = 1.0) -> void:
	strength = clampf(strength, 0.2, 4.0)
	var dir := direction.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var root := Node3D.new()
	get_parent().add_child(root)
	root.global_position = origin
	var blast := _make_droplet_burst(
		int(clampf(60.0 * strength, 24, 300)),  # amount
		0.15,                                    # emission radius
		24.0,                                    # cone spread degrees
		8.0 * strength, 12.0 * strength,         # fast, forward
		0.03, 0.09,                              # small droplets
		0.55,                                    # short-lived -> a quick shove
		dir,                                     # travel along the push direction
		Vector3(0, -4.0, 0))                     # light gravity so it sags a bit
	root.add_child(blast)
	blast.emitting = true
	blast.finished.connect(root.queue_free)

## Send a real wave -- a curved crest of translucent water that rises from the
## surface at `origin` and skims forward along `direction`, refracting the world
## behind it and foaming at the top, before fading out. Travel is forced
## horizontal (it rides the water; it can't be aimed up or down). `strength`
## scales its size and how far it reaches.
func send_wave(origin: Vector3, direction: Vector3, strength: float = 1.0) -> void:
	strength = clampf(strength, 0.3, 4.0)
	var travel_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	if travel_dir == Vector3.ZERO:
		travel_dir = Vector3.FORWARD

	var speed := 12.0
	var distance := 20.0 * strength
	var travel_time := distance / speed

	var mi := MeshInstance3D.new()
	mi.mesh = _build_wave_mesh(3.0 * strength, 1.3 * strength, 0.7 * strength, 0.5 * strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = WaveShader
	mat.set_shader_parameter("alpha_mul", 0.0)
	mi.material_override = mat

	get_parent().add_child(mi)
	mi.global_position = origin
	# Aim the crest (built facing -Z) along the travel direction.
	mi.look_at(origin + travel_dir, Vector3.UP)

	var set_alpha := func(a: float) -> void: mat.set_shader_parameter("alpha_mul", a)
	var tw := create_tween()
	tw.tween_method(set_alpha, 0.0, 1.0, 0.12)                                             # rise in
	tw.tween_property(mi, "global_position", origin + travel_dir * distance, travel_time)  # skim forward
	tw.tween_method(set_alpha, 1.0, 0.0, 0.35)                                             # fade out
	tw.tween_callback(mi.queue_free)

## Build a curved wave-crest sheet: highest and leading in the middle, tapering
## at the ends, with the top curling forward (toward -Z). UV.y carries the height
## fraction (0 base, 1 crest) for the shader's foam/tint.
func _build_wave_mesh(width: float, height: float, curl: float, bow: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 24
	var nv := 12
	for j in nv:
		for i in nu:
			var u0 := float(i) / float(nu)
			var u1 := float(i + 1) / float(nu)
			var v0 := float(j) / float(nv)
			var v1 := float(j + 1) / float(nv)
			var a := _wave_point(u0, v0, width, height, curl, bow)
			var b := _wave_point(u1, v0, width, height, curl, bow)
			var c := _wave_point(u1, v1, width, height, curl, bow)
			var d := _wave_point(u0, v1, width, height, curl, bow)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
			st.set_uv(Vector2(u1, v0)); st.add_vertex(b)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(c)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(c)
			st.set_uv(Vector2(u0, v1)); st.add_vertex(d)
	st.generate_normals()
	return st.commit()

func _wave_point(u: float, v: float, w: float, h: float, curl: float, bow: float) -> Vector3:
	var edge := sin(u * PI)                 # 0 at the ends, 1 in the middle
	var x := (u - 0.5) * w
	var y := v * h * (0.35 + 0.65 * edge)   # crest highest in the centre
	# Concave crescent (centre leads) plus the top curling forward, both toward -Z.
	var z := bow * (1.0 - edge) - curl * v * v
	return Vector3(x, y, z)

## Build one one-shot GPUParticles3D of ballistic blue droplets. Shared by the
## jet and crown layers of splash_at.
func _make_droplet_burst(amount: int, emit_radius: float, spread: float,
		vmin: float, vmax: float, scale_min: float, scale_max: float,
		lifetime: float, dir := Vector3(0, 1, 0),
		grav := Vector3(0, -12.0, 0)) -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = emit_radius
	mat.direction              = dir
	mat.spread                 = spread
	mat.initial_velocity_min   = vmin
	mat.initial_velocity_max   = vmax
	# A touch heavier than real gravity so it snaps up and falls back crisply.
	mat.gravity                = grav
	mat.damping_min            = 0.0
	mat.damping_max            = 0.0
	mat.scale_min              = scale_min
	mat.scale_max              = scale_max
	# Thin out as they fly, like droplets stretching and breaking up.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.15))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	mat.scale_curve = scale_tex
	mat.angular_velocity_min   = -300.0
	mat.angular_velocity_max   =  300.0

	# White + alpha only; the droplet shader supplies the blue. Stays opaque
	# then fades out over the last third of the arc.
	var grad := Gradient.new()
	grad.colors  = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	var mesh := SphereMesh.new()
	mesh.radius          = 0.5
	mesh.height          = 1.0
	mesh.radial_segments = 8
	mesh.rings           = 4
	var mmat := ShaderMaterial.new()
	mmat.shader          = DropletShader
	mmat.render_priority = 3
	mesh.material = mmat

	var p := GPUParticles3D.new()
	p.amount          = amount
	p.lifetime        = lifetime
	p.one_shot        = true
	p.explosiveness   = 1.0   # whole burst leaves at the instant of impact
	p.local_coords    = false
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 16, 16))
	p.process_material = mat
	p.draw_pass_1     = mesh
	return p

func _get_bodies_in_water() -> Array[RigidBody3D]:
	var result : Array[RigidBody3D] = []
	var water_y := global_position.y
	for child in get_parent().get_children():
		if child is RigidBody3D:
			var b := child as RigidBody3D
			if abs(b.global_position.y - water_y) < 3.0:
				result.append(b)
			if result.size() >= MAX_BODIES:
				break
	return result

func _spawn_splash(body: RigidBody3D) -> void:
	var s := SplashScene.instantiate()
	s.autoplay = false
	get_parent().add_child(s)
	s.global_position = Vector3(body.global_position.x, global_position.y + 0.5, body.global_position.z)
	s._follow = body
	s.finished.connect(s.queue_free)
	s.play()

func _reset_body(body: RigidBody3D) -> void:
	var pos_arr  : Array[Vector3] = []
	var time_arr : Array[float]   = []
	for i in SLOTS_PER_BODY:
		pos_arr.append(Vector3(99999, 0, 99999))
		time_arr.append(-9999.0)
	_bodies[body] = { "pos": pos_arr, "time": time_arr, "last": Vector3(99999, 0, 99999), "leaving": false, "leave_time": 0.0 }

func _ensure_body(body: RigidBody3D) -> void:
	if not _bodies.has(body):
		_reset_body(body)
		_spawn_splash(body)
	elif _bodies[body]["leaving"]:
		# Body re-entered water
		_bodies[body]["leaving"] = false
		_spawn_splash(body)

func _process(delta: float) -> void:
	if _mat == null:
		return
	_elapsed += delta
	# Drive the shader's wave clock from the same value the CPU height uses.
	_mat.set_shader_parameter("wave_time", _elapsed)

	var active := _get_bodies_in_water()

	# Mark bodies that left — record the exact time they left
	for b in _bodies.keys():
		if not active.has(b) and not _bodies[b]["leaving"]:
			_bodies[b]["leaving"]   = true
			_bodies[b]["leave_time"] = _elapsed

	# Remove leaving bodies after a fixed fade window (4 seconds)
	var fade_window : float = 4.0
	for b in _bodies.keys():
		if _bodies[b]["leaving"]:
			if (_elapsed - float(_bodies[b]["leave_time"])) > fade_window:
				_bodies.erase(b)

	for body in active:
		_ensure_body(body)
		var d   : Dictionary = _bodies[body]
		if d["leaving"]:
			continue
		var pos : Vector3    = body.global_position
		if pos.distance_to(d["last"]) >= MIN_MOVE_DIST:
			d["last"] = pos
			for i in range(SLOTS_PER_BODY - 1, 0, -1):
				d["pos"][i]  = d["pos"][i - 1]
				d["time"][i] = d["time"][i - 1]
			d["pos"][0]  = pos
			d["time"][0] = _elapsed

	var bodies_list : Array[RigidBody3D] = []
	for b in _bodies.keys():
		bodies_list.append(b as RigidBody3D)
	for b_idx in range(min(bodies_list.size(), MAX_BODIES)):
		var d    : Dictionary = _bodies[bodies_list[b_idx]]
		var base : int        = b_idx * SLOTS_PER_BODY
		for i in SLOTS_PER_BODY:
			_trail_pos[base + i] = d["pos"][i]
			_trail_age[base + i] = maxf(_elapsed - d["time"][i], 0.0)

	for b_idx in range(bodies_list.size(), MAX_BODIES):
		var base : int = b_idx * SLOTS_PER_BODY
		for i in SLOTS_PER_BODY:
			_trail_pos[base + i] = Vector3(99999, 0, 99999)
			_trail_age[base + i] = 9999.0

	_mat.set_shader_parameter("trail_pos", _trail_pos)
	_mat.set_shader_parameter("trail_age", _trail_age)

	# Wake particles: follow active body, only emit while moving
	var wake_active := false
	for b in _bodies.keys():
		if not _bodies[b]["leaving"]:
			_wake.global_position = Vector3(
				b.global_position.x,
				b.global_position.y - 0.8,
				b.global_position.z
			)
			wake_active = b.linear_velocity.length() > 0.4
			break
	_wake.emitting = wake_active

func _add_bubbles() -> void:
	get_parent().add_child(_bubbles)
	_bubbles.global_position = Vector3(global_position.x, global_position.y - 0.5, global_position.z)
	var m := _bubbles.draw_pass_1.surface_get_material(0) as ShaderMaterial
	if m:
		m.set_shader_parameter("water_y", global_position.y)
