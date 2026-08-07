## Bridges poolk's FluidBox to the API this game's player.gd expects (the
## same API water/ocean.gd used to provide, before this scene switched to
## poolk's interactive water). Two gaps to close:
##   - FluidBox.get_height_at() returns wave height *relative to the rest
##     surface*; player.gd wants an absolute world Y.
##   - FluidBox has no send_wave(); player.gd's water-power key expects one,
##     so translate it into a travelling dipole impulse.
extends "res://poolk/fluid_box.gd"

## The splash is a rising CROWN of actual water (a procedural water-sheet mesh
## that lifts out of the surface and bursts with foam), not the droplet-particle
## burst FluidBox ships with -- so an entry/exit splash reads as the pool water
## erupting, the same water as the surface.
const _SplashCrown := preload("res://water/splash.tscn")
const _WaveShader := preload("res://water/wave.gdshader")
const _DropletShader := preload("res://water/droplet.gdshader")


func get_height_at(world_pos: Vector3) -> float:
	return global_position.y + super.get_height_at(world_pos)


## The undisturbed surface, with no sim displacement on top -- FluidBox's
## heights are all relative to the node's own plane. player.gd needs the
## baseline separately from get_height_at so it can bound how far a depression
## in the sim is allowed to weaken buoyancy; the biggest depressions in this
## pool are the ones swimmers carve under themselves. See its _water_height().
func get_rest_height() -> float:
	return global_position.y


## A big forward-lancing wave for the water-power key: an actual crest of
## water that leaps up out of the surface and races forward, curling and
## foaming, the way a hard shove looks in a pool fight -- not just a bump in
## the height field, which reads as too subtle on its own.
##
## Two things happen, layered on top of each other:
##  - add_impulse() drives the real sim (so buoyant bodies actually get
##    pushed). In the sim's impulse shape (water_sim.gdshader) the
##    along-`direction` reach scales with radius_m * (1 + elongation), while
##    the perpendicular (sideways) extent is just radius_m -- so elongation is
##    what makes it shoot far ahead, and keeping radius_m fixed (not scaled by
##    strength) keeps it narrow instead of ballooning out to the sides as it
##    gets bigger. How long it lingers isn't set here -- that's the sim's
##    global wave_damping on the water base node, shared by every wave in the
##    pool, this one included.
##  - A standalone crest mesh (_build_wave_crest) is the actual "jumping out
##    of the water" visual: real geometry that rises well above the surface,
##    travels forward, and fades -- the sim alone can't produce that height on
##    a flat plane.
func send_wave(origin: Vector3, direction: Vector3, strength: float = 1.0) -> void:
	strength = clampf(strength, 0.3, 4.0)
	var travel_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	if travel_dir == Vector3.ZERO:
		travel_dir = Vector3.FORWARD

	add_impulse(origin, 0.42 * strength, 1.3, travel_dir, 1.0, 7.0 * strength)

	# A burst right where it launches -- water visibly kicking up as you shove.
	_spawn_splash(origin, 220.0 * strength, 1.0)

	_spawn_wave_crest(origin, travel_dir, strength)


## Spawns the actual crest geometry for send_wave(): rises fast (leaping out
## of the surface), skims forward, then fades. Frees itself when done.
func _spawn_wave_crest(origin: Vector3, travel_dir: Vector3, strength: float) -> void:
	var speed := 14.0
	var distance := 7.0 * strength
	var travel_time := distance / speed

	var mi := MeshInstance3D.new()
	# height/curl pushed hard so the crest genuinely rises above the surface
	# instead of reading as a ripple; bow keeps the lead-with-the-middle shape.
	mi.mesh = _build_wave_crest(2.2 * strength, 2.4 * strength, 1.3 * strength, 0.8 * strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _WaveShader
	mat.set_shader_parameter("alpha_mul", 0.0)
	mi.material_override = mat

	add_child(mi)
	mi.global_position = Vector3(origin.x, global_position.y, origin.z)
	mi.look_at(mi.global_position + travel_dir, Vector3.UP)

	# A dense cyan spray riding along with the crest for its whole trip -- the
	# mesh alone reads as a smooth wave, not a pool-fight shove throwing water
	# everywhere. local_coords = false so particles it's already thrown stay
	# put in world space as the emitter itself keeps moving forward, instead
	# of getting dragged along -- that's what makes it read as a trail.
	var spray := _make_cyan_spray(strength)
	add_child(spray)
	spray.global_position = mi.global_position
	spray.emitting = true

	var set_alpha := func(a: float) -> void: mat.set_shader_parameter("alpha_mul", a)
	var tw := create_tween()
	tw.tween_method(set_alpha, 0.0, 1.0, 0.06)                                                 # snap up fast
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position", mi.global_position + travel_dir * distance, travel_time)
	tw.tween_property(spray, "global_position", spray.global_position + travel_dir * distance, travel_time)
	tw.set_parallel(false)
	tw.tween_method(set_alpha, 1.0, 0.0, 0.3)                                                  # fall back and fade
	tw.tween_callback(mi.queue_free)
	tw.tween_callback(func() -> void: spray.emitting = false)
	tw.tween_interval(spray.lifetime)                                                          # let the tail fade
	tw.tween_callback(spray.queue_free)


## A dense, vivid-cyan droplet spray for send_wave()'s crest. Continuous
## (not one_shot) so it keeps throwing droplets for as long as it's emitting,
## which _spawn_wave_crest rides along with the travelling crest.
func _make_cyan_spray(strength: float) -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.6
	mat.direction              = Vector3(0, 1, 0)
	mat.spread                 = 65.0
	mat.flatness               = 0.25
	mat.initial_velocity_min   = 3.5
	mat.initial_velocity_max   = 8.0 * strength
	mat.gravity                = Vector3(0, -14.0, 0)
	mat.scale_min              = 0.05
	mat.scale_max              = 0.16
	mat.damping_min            = 0.2
	mat.damping_max            = 0.6
	mat.angular_velocity_min   = -260.0
	mat.angular_velocity_max   =  260.0

	# Strong cyan -- droplet.gdshader multiplies its base blue by COLOR.rgb, so
	# this pushes it past "water blue" into the vivid cyan spray you get from
	# an actual pool shove.
	var grad := Gradient.new()
	grad.colors  = PackedColorArray([
		Color(0.3, 1.0, 1.0, 1.0),
		Color(0.3, 1.0, 1.0, 1.0),
		Color(0.3, 1.0, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	var mesh := SphereMesh.new()
	mesh.radius          = 0.5
	mesh.height          = 1.0
	mesh.radial_segments = 6
	mesh.rings           = 3
	var mmat := ShaderMaterial.new()
	mmat.shader          = _DropletShader
	mmat.render_priority = 3
	mesh.material = mmat

	var p := GPUParticles3D.new()
	# "a shit ton" -- scales with strength like everything else about the wave.
	p.amount          = int(clampf(260.0 * strength, 80, 900))
	p.lifetime        = 0.55
	p.one_shot        = false
	p.explosiveness   = 0.0
	p.local_coords    = false
	p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 12, 20))
	p.process_material = mat
	p.draw_pass_1     = mesh
	return p


## Same crescent-crest shape as water/ocean.gd's wave builder: highest and
## leading in the middle, tapering at the ends, top curling forward (-Z).
## UV.y carries the height fraction (0 base, 1 crest) for the shader's foam.
func _build_wave_crest(width: float, height: float, curl: float, bow: float) -> ArrayMesh:
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
			var a := _wave_crest_point(u0, v0, width, height, curl, bow)
			var b := _wave_crest_point(u1, v0, width, height, curl, bow)
			var c := _wave_crest_point(u1, v1, width, height, curl, bow)
			var d := _wave_crest_point(u0, v1, width, height, curl, bow)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
			st.set_uv(Vector2(u1, v0)); st.add_vertex(b)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(c)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(c)
			st.set_uv(Vector2(u0, v1)); st.add_vertex(d)
	st.generate_normals()
	return st.commit()


func _wave_crest_point(u: float, v: float, w: float, h: float, curl: float, bow: float) -> Vector3:
	var edge := sin(u * PI)                 # 0 at the ends, 1 in the middle
	var x := (u - 0.5) * w
	var y := v * h * (0.35 + 0.65 * edge)   # crest highest in the centre
	# Concave crescent (centre leads) plus the top curling forward, both toward -Z.
	var z := bow * (1.0 - edge) - curl * v * v
	return Vector3(x, y, z)


## Override FluidBox's droplet-particle splash: spawn the water crown instead.
## `momentum` (mass x speed of the impact) scales how big and tall it is.
func _spawn_splash(pos: Vector3, momentum: float, _radius: float) -> void:
	var crown := _SplashCrown.instantiate()
	crown.autoplay = false
	add_child(crown)
	crown.global_position = Vector3(pos.x, global_position.y, pos.z)
	var t := clampf(momentum / 300.0, 0.0, 1.0)   # 0 = ripple, 1 = cannonball
	crown.scale = Vector3.ONE * lerpf(0.7, 2.2, t)
	crown.duration = lerpf(0.6, 0.9, t)
	crown.finished.connect(crown.queue_free)
	crown.play()
