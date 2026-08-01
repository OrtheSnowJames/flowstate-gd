extends RigidBody3D

const SWIM_GAIN: float = 20.0

## Top movement speed in m/s (reached at full momentum). Momentum scales speed
## from ~1/3 of this up to this value; raise it to make momentum more effective.
@export var swim_speed: float = 12.0
@export var mouse_sensitivity: float = 0.0025

@export var body_mass: float = 0.2

@export_group("Buoyancy")
## Fraction of the body resting below the surface at equilibrium. 0.5 = half
## submerged; smaller floats higher, larger sits deeper. This is the main knob.
@export_range(0.05, 1.0, 0.01) var target_submersion: float = 0.5
## Damping ratio for the vertical bob. 1.0 = critically damped (settles fast, no
## overshoot); >1 is sluggish, <1 bounces. The actual damping coefficient is
## derived from this and the spring stiffness so it can't accidentally bounce.
@export var damping_ratio: float = 1.1
## Resistance applied to movement while submerged.
@export var water_linear_drag: float = 3.0
## Half the body's height, used to measure how much of it is under water.
@export var body_half_height: float = 1.0
## Downward probe length used to detect ground for walking.
@export var ground_probe: float = 1.1
## Forward probe length used to detect a wall ahead while gliding.
@export var wall_probe: float = 0.7
@export var ocean_path: NodePath
# Momentum for how fast the player moves and later, attacks and combos and shit
@export var max_momentum: float = 10.0
@export var momentum_in_shallow_end: float = 2.0
@export var max_momentum_by_walking: float = 3.5
@export var momentum_needed_to_swim: float = 5.0

@export var dodge_momentum: float = 4.5
@export var momentum: float = 0.0
var dir: Vector3 = Vector3.ZERO
var can_move: bool = true
# Movement state: state of movement 👍
@export_enum(
	"idle", # 0
	"tread", # 1
	"swim_up", # 2
	"swim", # 3
	"glide", # 4
	"dodge", # 5
	"walk", # 6
) var movement_state: int = 0
var _ocean: Node = null

@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
var _underwater_mat: ShaderMaterial

var _pitch: float = 0.0
var _gravity: float = 9.8
# Tracks surface crossings so we splash once on entry, not every frame.
var _was_in_water: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mass = body_mass
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	# Keep the capsule upright; buoyancy/torque shouldn't tip the player over.
	lock_rotation = true
	if ocean_path:
		_ocean = get_node_or_null(ocean_path)
	_underwater_mat = ShaderMaterial.new()
	_underwater_mat.shader = load("res://water/underwater.gdshader")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.4)
		_camera.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	# Compute these once per tick; in_shallow_end() runs a raycast, so don't call
	# it (or _submersion) repeatedly below.
	var submersion := _submersion()
	var shallow := in_shallow_end()

	# Splash on entry: the frame we break the surface coming in (a dive or fall),
	# spawn droplets scaled by how hard we hit. Only fires on the crossing, not
	# while already submerged.
	var in_water := submersion > 0.15
	if in_water and not _was_in_water and _ocean and _ocean.has_method("splash_at"):
		_ocean.splash_at(
			Vector3(global_position.x, _water_height(), global_position.z),
			clampf(absf(linear_velocity.y) / 4.0, 0.6, 2.5))
	_was_in_water = in_water

	# Gravity stays on everywhere; buoyancy grows smoothly with submersion so the
	# body has one stable resting waterline (no on/off flip that causes bobbing).
	if submersion > 0.0:
		_apply_buoyancy(submersion)

	# Movement mode. You can swim wherever there's enough water by holding the swim
	# key. In the shallow end releasing it drops straight back to walking (no
	# gliding), since your feet can just touch down; in open water releasing it
	# glides as before.
	var wants_swim := Input.is_action_pressed("swim_key")
	if shallow:
		if wants_swim:
			_swim(delta)
		else:
			_walk(delta)
	elif submersion > 0.25:
		_swim(delta)
	else:
		_walk(delta)

	if shallow:
		momentum = max(momentum_in_shallow_end, momentum)

	# Water power (press 1): send a wave skimming across the surface in the
	# direction you're facing (horizontal only -- it rides the water, so it
	# starts at the surface height and can't be aimed up or down).
	if Input.is_action_just_pressed("water_power") and _ocean and _ocean.has_method("send_wave"):
		var forward := -transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var origin := global_position + forward * 1.0
		origin.y = _water_height()
		_ocean.send_wave(origin, forward, 1.0)

## Fraction of the body below the water surface: 0 fully out, 1 fully under.
func _submersion() -> float:
	var bottom := global_position.y - body_half_height
	return clampf((_water_height() - bottom) / (2.0 * body_half_height), 0.0, 1.0)

## True when the player is standing on the bottom while still partly in the
## water -- the shallow end, where they should walk rather than swim.
func in_shallow_end() -> bool:
	return _submersion() > 0.0 and _is_on_floor()

func _swim_up_animation_time() -> float:
	if momentum >= momentum_needed_to_swim:
		return 0.0

	var t = momentum / momentum_needed_to_swim
	return lerp(0.5, 1.5, t)

## World-space height of the ocean surface directly above/below the player.
func _water_height() -> float:
	if _ocean and _ocean.has_method("get_height_at"):
		return _ocean.get_height_at(global_position)
	return 0.0

## True when something solid is within `ground_probe` below the body.
func _is_on_floor() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * ground_probe)
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()

func _walk(delta: float) -> void:
	can_move = true
	# Same movement actions as swimming (WASD + arrows) so controls are consistent
	# everywhere -- walking in the shallows no longer needs the arrow keys.
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# walk while moving, idle when standing still
	movement_state = 6 if direction else 0

	# Momentum is the only speed modifier, so walking/wading builds momentum too --
	# but only up to max_momentum_by_walking, which keeps it slower than a full
	# swim. It bleeds back off when you stop.
	if direction:
		momentum = move_toward(momentum, max_momentum_by_walking, SWIM_GAIN * delta)
	else:
		momentum = move_toward(momentum, 0.0, SWIM_GAIN * delta)

	# Speed comes from momentum via the shared drag + thrust, so wading has the
	# same water resistance as swimming, just capped lower.
	_apply_swim_motion(direction, momentum / max_momentum)

func _swim(delta: float) -> void:
	if not Input.is_action_pressed("swim_key"):
		_glide(delta)
		return
	# Actively swimming re-enables movement after a tread stopped it, so the
	# player isn't permanently frozen once momentum drains to zero.
	can_move = true
	# Momentum (0.0 -> 1.0)
	var t := momentum / max_momentum

	# Intentional swim thrust direction (horizontal + look-based vertical).
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	dir = (_camera.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	dir.y = (_camera.global_transform.basis * Vector3(0, 0, -1)).y * input_dir.length()

	# Build momentum. During the swim-up wind-up, pace it so momentum reaches the
	# swim threshold over _swim_up_animation_time() seconds; once swimming, keep
	# building toward max the usual way (fast at first, slow near max).
	var swim_up_time := _swim_up_animation_time()
	if swim_up_time > 0.0:
		momentum += momentum_needed_to_swim / swim_up_time * delta
	else:
		momentum += SWIM_GAIN * pow(1.0 - t, 2.0) * delta
	momentum = min(momentum, max_momentum)

	# swim_up is the wind-up phase spent building the momentum needed to swim
	# (see _swim_up_animation_time); once past the threshold it's a full swim.
	movement_state = 3 if momentum >= momentum_needed_to_swim else 2

	# Drag + thrust, shared with gliding so both top out at the same speed.
	_apply_swim_motion(dir, t)

func _glide(delta: float) -> void:
	# go along path, conserving momentum but not gaining any
	# basically like swimming but lose momentum
	# if momentum reaches zero, stop gliding and tread
	# Coast along the last heading flattened to horizontal, so a glide doesn't
	# drift up or down from wherever the camera was pointing when you let go.
	var glide_dir := Vector3(dir.x, 0.0, dir.z)

	# Tap forward to cancel the glide, or stop dead if we run into a wall.
	if Input.is_action_just_pressed("forward") or _wall_ahead(glide_dir):
		_stop_gliding()
		return

	if momentum > 0.0:
		movement_state = 4  # glide
		momentum -= SWIM_GAIN * delta
		var t = momentum / max_momentum
		_apply_swim_motion(glide_dir, t)
	else:
		momentum = 0.0
		_tread()

## Water drag plus forward thrust for the given momentum fraction `t` and move
## direction. Shared by swimming and gliding so both settle at the same speed
## for the same momentum -- gliding no longer coasts faster than swimming.
func _apply_swim_motion(move_dir: Vector3, t: float) -> void:
	var v := linear_velocity
	var drag: float = lerp(water_linear_drag * 1.5, water_linear_drag * 0.5, t)
	_apply_central_force(Vector3(-v.x, 0.0, -v.z) * drag * mass)
	if move_dir.length() > 0.01:
		var swim_force: float = lerp(swim_speed * 0.5, swim_speed * 1.5, t)
		_apply_central_force(move_dir.normalized() * swim_force * mass)

## True when a solid surface is within `wall_probe` ahead along `direction`.
func _wall_ahead(direction: Vector3) -> bool:
	if direction.length() < 0.01:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + direction.normalized() * wall_probe)
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()

## Halt a glide: kill horizontal speed and drop back to treading.
func _stop_gliding() -> void:
	linear_velocity.x = 0.0
	linear_velocity.z = 0.0
	_tread()

func _tread() -> void:
	movement_state = 1  # tread
	# reset momentum
	momentum = 0.0
	# stop movement
	can_move = false


## Archimedes buoyancy: upward acceleration is proportional to how much of the
## body is submerged. It's scaled so that at `target_submersion` the buoyant
## force exactly cancels gravity -- that's the stable resting waterline. As the
## body rises submersion drops and gravity wins; as it sinks buoyancy wins, so
## there's a single equilibrium and no on/off bobbing. Mass cancels out.
func _apply_buoyancy(submersion: float) -> void:
	var v := linear_velocity
	# Lift: submersion/target * g. At the target depth this equals gravity (which
	# the engine still applies), so the net vertical force is zero there -- the
	# stable resting waterline.
	var lift_accel := submersion / target_submersion * _gravity
	# Auto-critical damping: the spring's stiffness is k = g / (2h * target), so a
	# damping coefficient of 2*ratio*sqrt(k) gives the requested damping ratio and
	# guarantees no bounce for ratio >= 1, whatever the target is.
	var k := _gravity / (2.0 * body_half_height * target_submersion)
	var damping := 2.0 * damping_ratio * sqrt(k)
	var accel := lift_accel - v.y * damping
	# Buoyancy is passive physics -- apply it directly, never gated by can_move,
	# or the player would sink whenever movement is disabled (e.g. after treading).
	apply_central_force(Vector3.UP * accel * mass)

func _apply_central_force(force: Vector3) -> void:
	if can_move:
		apply_central_force(force)
