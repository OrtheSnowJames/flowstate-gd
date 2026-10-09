# bridges poolks fluidbox to the api this games player gd expects the same api
extends "res://poolk/fluid_box.gd"

# the splash is a rising crown of actual water a procedural water sheet mesh
const _SplashCrown := preload("res://water/splash.tscn")
const _WaveShader := preload("res://water/wave.gdshader")
const _DropletShader := preload("res://water/droplet.gdshader")


func get_height_at(world_pos: Vector3) -> float:
	return global_position.y + super.get_height_at(world_pos)


# the undisturbed surface with no sim displacement on top fluidboxs heights are all relative
func get_rest_height() -> float:
	return global_position.y


# a big forward lancing wave for the water power key an actual crest of
func send_wave(origin: Vector3, direction: Vector3, strength: float = 1.0,
		caster: Node3D = null, apply_hits: bool = true,
		damage_min: float = _stamina_damage_power_min,
		damage_max: float = _stamina_damage_power_max) -> void:
	strength = clampf(strength, 0.3, 4.0)
	var travel_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	if travel_dir == Vector3.ZERO:
		travel_dir = Vector3.FORWARD

	var max_distance := 7.0 * strength
	var hit := _find_wave_target(origin, travel_dir, max_distance, _hit_half_width * strength, caster)
	var reach := max_distance
	if not hit.is_empty():
		# the wave stops at whatever it ran into for everyone thats what it looks
		reach = hit.along
		if apply_hits:
			_knockback(hit.body, travel_dir, _knockback_impulse_power * strength)
			# long range lance a hit that lands at full extension is harder to land
			_apply_hit_damage(hit.body, strength, hit.along, max_distance,
					damage_min, damage_max, false)

	# elongation drives the sims along direction reach see the class comment above so shrinking
	add_impulse(origin, 0.42 * strength, 1.3, travel_dir, 1.0, 7.0 * strength * (reach / max_distance))

	# a burst right where it launches water visibly kicking up as you shove
	_spawn_splash(origin, 220.0 * strength, 1.0)

	_spawn_wave_crest(origin, travel_dir, strength, reach)


# close range counterpart to send_wave for the water attack key a bigger denser burst
func send_attack_wave(origin: Vector3, direction: Vector3, strength: float = 1.0,
		caster: Node3D = null, apply_hits: bool = true,
		damage_min: float = _stamina_damage_attack_min,
		damage_max: float = _stamina_damage_attack_max) -> void:
	strength = clampf(strength, 0.3, 4.0)
	var travel_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	if travel_dir == Vector3.ZERO:
		travel_dir = Vector3.FORWARD

	var max_distance := 7.0 * strength * 0.28
	# wider hit window than water power its a close range haymaker not a thin
	var hit := _find_wave_target(origin, travel_dir, max_distance, _hit_half_width * strength * 1.6, caster)
	var reach := max_distance
	if not hit.is_empty():
		reach = hit.along
		if apply_hits:
			_knockback(hit.body, travel_dir, _knockback_impulse_attack * strength)
			# point blank haymaker the opposite of water power the closer the hit lands the
			_apply_hit_damage(hit.body, strength, hit.along, max_distance,
					damage_min, damage_max, true)

	add_impulse(origin, 0.6 * strength, 2.2 * strength, travel_dir, 1.0, 1.4 * (reach / max_distance))

	# a much bigger kick up right at the point of impact
	_spawn_splash(origin, 380.0 * strength, 1.3)

	_spawn_wave_crest(origin, travel_dir, strength, reach, 1.8, 3.0)


# live water walls keyed by the caster that raised each one its a hold
var _walls: Dictionary = {}


# a stationary wall of water for the water wall key rises on the first
func start_water_wall(origin: Vector3, direction: Vector3, strength: float = 1.0,
		caster: Node3D = null) -> void:
	strength = clampf(strength, 0.3, 4.0)
	var facing := Vector3(direction.x, 0.0, direction.z).normalized()
	if facing == Vector3.ZERO:
		facing = Vector3.FORWARD

	var key := _wall_key(caster)
	if _walls.has(key) and is_instance_valid(_walls[key].mesh):
		# already up follow the caster instead of restarting the rise
		_position_water_wall(_walls[key], origin, facing)
		return

	var mi := MeshInstance3D.new()
	# tall and wide barely curling or bowed a flat fronted wall not a lancing
	mi.mesh = _build_wave_crest(3.4 * strength, 2.6 * strength, 0.3 * strength, 0.2 * strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _WaveShader
	mat.set_shader_parameter("alpha_mul", 0.0)
	mi.material_override = mat
	add_child(mi)

	var spray := _make_cyan_spray(strength, 1.5, 1.2)
	add_child(spray)
	spray.emitting = true

	var wall := {"mesh": mi, "spray": spray, "mat": mat}
	_walls[key] = wall
	_position_water_wall(wall, origin, facing)

	var set_alpha := func(a: float) -> void: mat.set_shader_parameter("alpha_mul", a)
	create_tween().tween_method(set_alpha, 0.0, 1.0, 0.12) # rise holds at 1 0 until stop_water_wall

	# water visibly surging upward at the base not just the crest mesh appearing out
	_spawn_splash(origin, 260.0 * strength, 1.4)


# identifies whose wall is whose falls back to 0 for a null caster so
func _wall_key(caster: Node3D) -> int:
	return caster.get_instance_id() if is_instance_valid(caster) else 0


func _position_water_wall(wall: Dictionary, origin: Vector3, facing: Vector3) -> void:
	var pos := Vector3(origin.x, global_position.y, origin.z)
	wall.mesh.global_position = pos
	wall.mesh.look_at(pos + facing, Vector3.UP)
	wall.spray.global_position = pos


# water wall key released that casters wall falls back and fades then frees safe
func stop_water_wall(caster: Node3D = null) -> void:
	var key := _wall_key(caster)
	if not _walls.has(key):
		return
	var wall: Dictionary = _walls[key]
	_walls.erase(key)
	if not is_instance_valid(wall.mesh):
		return
	var mi: MeshInstance3D = wall.mesh
	var spray: GPUParticles3D = wall.spray
	var mat: ShaderMaterial = wall.mat

	var set_alpha := func(a: float) -> void: mat.set_shader_parameter("alpha_mul", a)
	var tw := create_tween()
	tw.tween_method(set_alpha, 1.0, 0.0, 0.35) # fall back and fade
	tw.tween_callback(mi.queue_free)
	tw.tween_callback(func() -> void: spray.emitting = false)
	tw.tween_interval(spray.lifetime) # let the tail fade
	tw.tween_callback(spray.queue_free)


# half width m of the path a wave can hit along at strength 1
const _hit_half_width := 1.1
# impulse roughly kg m s handed to apply_central_impulse on a hit at strength 1
const _knockback_impulse_power := 40.0
const _knockback_impulse_attack := 90.0

# stamina damage range at strength 1 before _apply_hit_damage picks a point along it based
const _stamina_damage_power_min := 8.0
const _stamina_damage_power_max := 30.0
const _stamina_damage_attack_min := 35.0
const _stamina_damage_attack_max := 65.0


# looks for the nearest body a travelling wave should stop at instead of sailing
func _find_wave_target(origin: Vector3, travel_dir: Vector3, max_distance: float,
		hit_half_width: float, exclude: Node3D) -> Dictionary:
	var best: Dictionary = {}
	var best_along := INF
	for state in _tracked.values():
		var body = state.body
		if not is_instance_valid(body) or body == exclude:
			continue
		var to_body: Vector3 = body.global_position - origin
		var along := to_body.dot(travel_dir)
		if along < 0.0 or along > max_distance or along >= best_along:
			continue
		var lateral := (to_body - travel_dir * along).length()
		if lateral > hit_half_width + state.r:
			continue
		best_along = along
		best = {"body": body, "along": along}
	return best


# shoves a hit body back along the waves travel direction rigidbody3d only the only
func _knockback(body: Node3D, travel_dir: Vector3, impulse: float) -> void:
	if not (body is RigidBody3D):
		return
	_send_to_owner(body, "net_apply_impulse", [travel_dir * impulse],
			func() -> void: body.apply_central_impulse(travel_dir * impulse))


# stamina damage on a landed hit scaled by strength and by how far along
func _apply_hit_damage(body: Node3D, strength: float, along: float, max_distance: float,
		min_damage: float, max_damage: float, closer_hurts_more: bool) -> void:
	if not body.has_method("take_stamina_damage"):
		return
	var t := clampf(along / max_distance, 0.0, 1.0)
	if closer_hurts_more:
		t = 1.0 - t
	var amount := lerpf(min_damage, max_damage, t) * strength
	# ask the victim to hurt itself rather than editing their stamina from here stamina
	_send_to_owner(body, "take_stamina_damage", [amount],
			func() -> void: body.take_stamina_damage(amount))


# runs method on body wherever that body is authoritative directly when thats us over
func _send_to_owner(body: Node3D, method: String, args: Array, local: Callable) -> void:
	var owner_peer := body.get_multiplayer_authority()
	if owner_peer == multiplayer.get_unique_id():
		local.call()
	elif body.has_method(method):
		body.rpc_id.callv([owner_peer, method] + args)


# spawns the actual crest geometry for send_wave send_attack_wave rises fast leaping out of the
func _spawn_wave_crest(origin: Vector3, travel_dir: Vector3, strength: float,
		distance: float, size_mult: float = 1.0, particle_mult: float = 1.0) -> void:
	var speed := 14.0
	var travel_time := distance / speed

	var mi := MeshInstance3D.new()
	# height curl kept modest so the crest rides level with the player instead of
	mi.mesh = _build_wave_crest(
		2.2 * strength * size_mult, 1.1 * strength * size_mult,
		0.6 * strength * size_mult, 0.8 * strength * size_mult)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _WaveShader
	mat.set_shader_parameter("alpha_mul", 0.0)
	mi.material_override = mat

	add_child(mi)
	mi.global_position = Vector3(origin.x, global_position.y, origin.z)
	mi.look_at(mi.global_position + travel_dir, Vector3.UP)

	# a dense cyan spray riding along with the crest for its whole trip the
	var spray := _make_cyan_spray(strength, particle_mult, size_mult)
	add_child(spray)
	spray.global_position = mi.global_position
	spray.emitting = true

	var set_alpha := func(a: float) -> void: mat.set_shader_parameter("alpha_mul", a)
	var tw := create_tween()
	tw.tween_method(set_alpha, 0.0, 1.0, 0.06) # snap up fast
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position", mi.global_position + travel_dir * distance, travel_time)
	tw.tween_property(spray, "global_position", spray.global_position + travel_dir * distance, travel_time)
	tw.set_parallel(false)
	tw.tween_method(set_alpha, 1.0, 0.0, 0.3) # fall back and fade
	tw.tween_callback(mi.queue_free)
	tw.tween_callback(func() -> void: spray.emitting = false)
	tw.tween_interval(spray.lifetime) # let the tail fade
	tw.tween_callback(spray.queue_free)


# a dense vivid cyan droplet spray for _spawn_wave_crest continuous not one_shot so it keeps
func _make_cyan_spray(strength: float, particle_mult: float = 1.0, size_mult: float = 1.0) -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.6 * size_mult
	mat.direction              = Vector3(0, 1, 0)
	mat.spread                 = 65.0
	mat.flatness               = 0.25
	mat.initial_velocity_min   = 3.5
	mat.initial_velocity_max   = 8.0 * strength
	mat.gravity                = Vector3(0, -14.0, 0)
	mat.scale_min              = 0.05 * size_mult
	mat.scale_max              = 0.16 * size_mult
	mat.damping_min            = 0.2
	mat.damping_max            = 0.6
	mat.angular_velocity_min   = -260.0
	mat.angular_velocity_max   =  260.0

	# strong cyan droplet gdshader multiplies its base blue by color rgb so this pushes
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
	# a shit ton scales with strength like everything else about the wave
	p.amount          = int(clampf(260.0 * strength * particle_mult, 80, 2000))
	p.lifetime        = 0.55
	p.one_shot        = false
	p.explosiveness   = 0.0
	p.local_coords    = false
	p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 12, 20))
	p.process_material = mat
	p.draw_pass_1     = mesh
	return p


# same crescent crest shape as water ocean gds wave builder highest and leading in
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
	var edge := sin(u * PI) # 0 at the ends 1 in the middle
	var x := (u - 0.5) * w
	var y := v * h * (0.35 + 0.65 * edge) # crest highest in the centre
	# concave crescent centre leads plus the top curling forward both toward z
	var z := bow * (1.0 - edge) - curl * v * v
	return Vector3(x, y, z)


# override fluidboxs droplet particle splash spawn the water crown instead momentum mass x speed
func _spawn_splash(pos: Vector3, momentum: float, _radius: float) -> void:
	var crown := _SplashCrown.instantiate()
	crown.autoplay = false
	add_child(crown)
	crown.global_position = Vector3(pos.x, global_position.y, pos.z)
	var t := clampf(momentum / 300.0, 0.0, 1.0) # 0 ripple 1 cannonball
	crown.scale = Vector3.ONE * lerpf(0.7, 2.2, t)
	crown.duration = lerpf(0.6, 0.9, t)
	crown.finished.connect(crown.queue_free)
	crown.play()
