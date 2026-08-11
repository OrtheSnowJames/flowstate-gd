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
##
## `caster` is excluded from hit detection (see _find_wave_target) so the wave
## can't knock back whoever just fired it.
##
## `apply_hits` splits showing the wave from resolving it. In multiplayer every
## peer runs this to draw the same wave (player.gd's net_cast_water_move is
## call_local), but only the peer that actually cast passes true -- otherwise
## each peer would independently decide the wave connected and the victim would
## be knocked back and damaged once per player in the game.
func send_wave(origin: Vector3, direction: Vector3, strength: float = 1.0,
		caster: Node3D = null, apply_hits: bool = true) -> void:
	strength = clampf(strength, 0.3, 4.0)
	var travel_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	if travel_dir == Vector3.ZERO:
		travel_dir = Vector3.FORWARD

	var max_distance := 7.0 * strength
	var hit := _find_wave_target(origin, travel_dir, max_distance, _hit_half_width * strength, caster)
	var reach := max_distance
	if not hit.is_empty():
		# The wave stops at whatever it ran into for everyone -- that's what it
		# looks like, not a question of who resolves the hit -- but only the
		# casting peer turns that into knockback and damage.
		reach = hit.along
		if apply_hits:
			_knockback(hit.body, travel_dir, _knockback_impulse_power * strength)
			# Long-range lance: a hit that lands at full extension is harder to
			# land and hits harder -- distance is the reward, not the penalty.
			_apply_hit_damage(hit.body, strength, hit.along, max_distance,
					_stamina_damage_power_min, _stamina_damage_power_max, false)

	# elongation drives the sim's along-direction reach (see the class comment
	# above), so shrinking it with the same fraction the crest got clipped by
	# stops the real water push at the hit too, not just the visual.
	add_impulse(origin, 0.42 * strength, 1.3, travel_dir, 1.0, 7.0 * strength * (reach / max_distance))

	# A burst right where it launches -- water visibly kicking up as you shove.
	_spawn_splash(origin, 220.0 * strength, 1.0)

	_spawn_wave_crest(origin, travel_dir, strength, reach)


## Close-range counterpart to send_wave() for the water-attack key: a bigger,
## denser burst that barely travels at all -- a shove right in front of you
## instead of a lance skimming across the pool. Same two-layer approach
## (add_impulse for the real sim push, a crest mesh for the "water leaping up"
## visual), just retuned: elongation stays low and fixed instead of scaling
## with strength (that's what kept send_wave's reach growing -- here reach
## should stay short no matter how hard you hit), while radius, strength_m,
## and the crest/particle sizing all scale up for a bigger, rounder blast.
## `apply_hits` works exactly as it does in send_wave() -- only the casting
## peer resolves the hit, everyone else just draws the wave.
func send_attack_wave(origin: Vector3, direction: Vector3, strength: float = 1.0,
		caster: Node3D = null, apply_hits: bool = true) -> void:
	strength = clampf(strength, 0.3, 4.0)
	var travel_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	if travel_dir == Vector3.ZERO:
		travel_dir = Vector3.FORWARD

	var max_distance := 7.0 * strength * 0.28
	# Wider hit window than water power -- it's a close-range haymaker, not a
	# thin lance, so it shouldn't need a dead-on line hit to land.
	var hit := _find_wave_target(origin, travel_dir, max_distance, _hit_half_width * strength * 1.6, caster)
	var reach := max_distance
	if not hit.is_empty():
		reach = hit.along
		if apply_hits:
			_knockback(hit.body, travel_dir, _knockback_impulse_attack * strength)
			# Point-blank haymaker: the opposite of water power -- the closer the
			# hit lands, the more it hurts.
			_apply_hit_damage(hit.body, strength, hit.along, max_distance,
					_stamina_damage_attack_min, _stamina_damage_attack_max, true)

	add_impulse(origin, 0.6 * strength, 2.2 * strength, travel_dir, 1.0, 1.4 * (reach / max_distance))

	# A much bigger kick-up right at the point of impact.
	_spawn_splash(origin, 380.0 * strength, 1.3)

	_spawn_wave_crest(origin, travel_dir, strength, reach, 1.8, 3.0)


## Live water walls, keyed by the caster that raised each one. It's a
## hold-to-sustain move, so a wall persists across frames and has to be found
## again to follow its caster and to drop when they let go -- and with more
## than one player in the pool, several can be up at once. Keyed by caster
## instance id rather than a single set of refs: sharing one wall between two
## players holding the key made each one's updates yank the other's wall
## around, and whoever released first tore down both.
##
## caster id -> { "mesh": MeshInstance3D, "spray": GPUParticles3D, "mat": ShaderMaterial }
var _walls: Dictionary = {}


## A stationary wall of water for the water-wall key: rises on the first call
## and then just follows its caster (via repeated calls, one per held frame)
## for as long as it's held -- see stop_water_wall() for when the key is
## released. Doesn't do anything yet -- no push, no blocking incoming waves --
## this is just the visual: it's the shape a future defend/block move will
## hang its actual behavior off of. Reuses the crest mesh but built tall and
## flat-fronted instead of a curling lance, and it never gets a travel tween
## -- it rises and stays put (repositioning to track the caster instead of
## sliding), unlike send_wave's crest skimming forward. Deliberately doesn't
## touch add_impulse: the real sim isn't disturbed at all, so there's nothing
## here to later conflict with defend logic reading or shaping the sim's
## height field at this same spot.
func start_water_wall(origin: Vector3, direction: Vector3, strength: float = 1.0,
		caster: Node3D = null) -> void:
	strength = clampf(strength, 0.3, 4.0)
	var facing := Vector3(direction.x, 0.0, direction.z).normalized()
	if facing == Vector3.ZERO:
		facing = Vector3.FORWARD

	var key := _wall_key(caster)
	if _walls.has(key) and is_instance_valid(_walls[key].mesh):
		# Already up -- follow the caster instead of restarting the rise.
		_position_water_wall(_walls[key], origin, facing)
		return

	var mi := MeshInstance3D.new()
	# Tall and wide, barely curling or bowed -- a flat-fronted wall, not a
	# lancing crest.
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
	create_tween().tween_method(set_alpha, 0.0, 1.0, 0.12)   # rise; holds at 1.0 until stop_water_wall

	# Water visibly surging upward at the base, not just the crest mesh
	# appearing out of nowhere.
	_spawn_splash(origin, 260.0 * strength, 1.4)


## Identifies whose wall is whose. Falls back to 0 for a null caster so
## single-player calls that don't pass one still get a consistent slot.
func _wall_key(caster: Node3D) -> int:
	return caster.get_instance_id() if is_instance_valid(caster) else 0


func _position_water_wall(wall: Dictionary, origin: Vector3, facing: Vector3) -> void:
	var pos := Vector3(origin.x, global_position.y, origin.z)
	wall.mesh.global_position = pos
	wall.mesh.look_at(pos + facing, Vector3.UP)
	wall.spray.global_position = pos


## Water-wall key released: that caster's wall falls back and fades, then
## frees. Safe to call even when they have no wall up (player.gd calls it
## unconditionally every frame the key isn't held) -- it's a no-op past the
## guard below, and it only ever touches the wall belonging to `caster`.
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
	tw.tween_method(set_alpha, 1.0, 0.0, 0.35)                                                 # fall back and fade
	tw.tween_callback(mi.queue_free)
	tw.tween_callback(func() -> void: spray.emitting = false)
	tw.tween_interval(spray.lifetime)                                                          # let the tail fade
	tw.tween_callback(spray.queue_free)


## Half-width (m) of the path a wave can hit along at strength 1 -- see
## _find_wave_target(). Scales with strength like everything else about the
## wave, same as the crest's own width.
const _hit_half_width := 1.1
## Impulse (roughly kg*m/s) handed to apply_central_impulse() on a hit, at
## strength 1. Water attack hits noticeably harder -- it's the close-range,
## high-commitment option, so the payoff should read as bigger.
const _knockback_impulse_power := 40.0
const _knockback_impulse_attack := 90.0

## Stamina damage range at strength 1, before _apply_hit_damage() picks a
## point along it based on where the hit landed. Water power is the
## long-range lance -- min is a graze right in front of you, max is a hit
## that landed at full extension. Water attack starts already well above
## water power's max (it's meant to hurt a lot, full stop) and climbs even
## higher the more point-blank the hit -- the opposite end of the range from
## water power, since it's the close-range option.
const _stamina_damage_power_min := 8.0
const _stamina_damage_power_max := 30.0
const _stamina_damage_attack_min := 35.0
const _stamina_damage_attack_max := 65.0


## Looks for the nearest body a travelling wave should stop at instead of
## sailing through. Only searches bodies FluidBox is already tracking as
## "in the water" (see _tracked in fluid_box.gd, fed by its own Area3D overlap
## detection) -- so this only ever finds things that make sense to shove
## (PushCube, another swimmer), never the static pool floor/walls, and needs
## no raycast or extra collision setup of its own.
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


## Shoves a hit body back along the wave's travel direction. RigidBody3D only
## -- the only kind of body this pool tracks that can meaningfully receive an
## impulse (see _find_wave_target).
##
## The push has to happen wherever that body's physics actually run, which is
## its multiplayer authority: a player's own peer for a swimmer, the host for
## PushCube. Applying it here instead would be applying it to a frozen puppet
## (see player.gd's _setup_remote_body and synced_prop.gd) -- the impulse would
## do nothing at all, and the next replicated transform would overwrite it.
func _knockback(body: Node3D, travel_dir: Vector3, impulse: float) -> void:
	if not (body is RigidBody3D):
		return
	_send_to_owner(body, "net_apply_impulse", [travel_dir * impulse],
			func() -> void: body.apply_central_impulse(travel_dir * impulse))


## Stamina damage on a landed hit, scaled by strength and by how far along
## the wave's own path (0..max_distance) the hit landed. `closer_hurts_more`
## flips which end of that range pays out more: false for water power (a hit
## at full extension -- harder to land -- hurts more), true for water attack
## (a hit right on top of you hurts more). Duck-typed via
## has_method("take_stamina_damage") -- PushCube and anything else without
## one just silently takes no damage, same reasoning as _knockback() checking
## for RigidBody3D.
func _apply_hit_damage(body: Node3D, strength: float, along: float, max_distance: float,
		min_damage: float, max_damage: float, closer_hurts_more: bool) -> void:
	if not body.has_method("take_stamina_damage"):
		return
	var t := clampf(along / max_distance, 0.0, 1.0)
	if closer_hurts_more:
		t = 1.0 - t
	var amount := lerpf(min_damage, max_damage, t) * strength
	# Ask the victim to hurt itself rather than editing their stamina from here.
	# Stamina lives on the peer that owns that body, and only that peer knows
	# whether they're holding a water wall up to halve the hit (player.gd's
	# take_stamina_damage) -- a number computed here would be both wrong and
	# invisible to everyone else.
	_send_to_owner(body, "take_stamina_damage", [amount],
			func() -> void: body.take_stamina_damage(amount))


## Runs `method` on `body` wherever that body is authoritative: directly when
## that's us, over RPC otherwise.
##
## The `local` fallback also covers single-player transparently -- with no
## connection our unique id is 1 and so is every body's default authority, so
## the comparison is true and nothing is sent anywhere.
func _send_to_owner(body: Node3D, method: String, args: Array, local: Callable) -> void:
	var owner_peer := body.get_multiplayer_authority()
	if owner_peer == multiplayer.get_unique_id():
		local.call()
	elif body.has_method(method):
		body.rpc_id.callv([owner_peer, method] + args)


## Spawns the actual crest geometry for send_wave()/send_attack_wave(): rises
## fast (leaping out of the surface), skims forward, then fades. Frees itself
## when done. `distance` is the absolute distance it travels before fading --
## callers clip it to wherever _find_wave_target says the wave stops, so a
## blocked wave visibly stops at the object instead of sailing through it.
## size_mult/particle_mult let send_attack_wave() reuse this for a bigger,
## denser burst instead of duplicating the whole thing.
func _spawn_wave_crest(origin: Vector3, travel_dir: Vector3, strength: float,
		distance: float, size_mult: float = 1.0, particle_mult: float = 1.0) -> void:
	var speed := 14.0
	var travel_time := distance / speed

	var mi := MeshInstance3D.new()
	# height/curl kept modest so the crest rides level with the player instead
	# of towering over them; bow keeps the lead-with-the-middle shape.
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

	# A dense cyan spray riding along with the crest for its whole trip -- the
	# mesh alone reads as a smooth wave, not a pool-fight shove throwing water
	# everywhere. local_coords = false so particles it's already thrown stay
	# put in world space as the emitter itself keeps moving forward, instead
	# of getting dragged along -- that's what makes it read as a trail.
	var spray := _make_cyan_spray(strength, particle_mult, size_mult)
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


## A dense, vivid-cyan droplet spray for _spawn_wave_crest(). Continuous (not
## one_shot) so it keeps throwing droplets for as long as it's emitting, which
## _spawn_wave_crest rides along with the travelling crest. particle_mult and
## size_mult let send_attack_wave() ask for a much heavier, chunkier spray.
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
	p.amount          = int(clampf(260.0 * strength * particle_mult, 80, 2000))
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
