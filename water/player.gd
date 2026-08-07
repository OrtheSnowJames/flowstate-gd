extends RigidBody3D

enum MovementState {
	IDLE,
	TREAD,
	SWIM_UP,
	SWIM,
	GLIDE,
	DODGE,
	WALK,
	JUMP,
}

const DEBUG_IN_SHALLOW_WATER: bool = true

const SWIM_GAIN: float = 10.0
const DODGE_DOUBLE_TAP_TIME := 0.25
## Grace window for the backstroke -> forward-stroke flip: how long after
## last holding S a W press still counts as "flip out of the backstroke".
## Needed because requiring S and W to overlap on the exact same physics tick
## (the old approach) is next to impossible to land on purpose -- there's
## almost always at least one frame's gap between releasing one key and
## pressing the other.
const BACKSTROKE_FLIP_WINDOW := 0.25
var last_a_press := -1000.0
var last_d_press := -1000.0


## Top movement speed in m/s (reached at full momentum). Momentum scales speed
## from ~1/3 of this up to this value; raise it to make momentum more effective.
@export var swim_speed: float = 12.0
## Radians/second the body (and camera, which follows its yaw) turns while
## holding A/D -- these no longer strafe, see _turn_from_input.
@export var turn_speed: float = 2.5

@export_group("Camera")
## Camera starts pitched down by this many degrees so the rig (already raised
## above head height) reads as an overhead view instead of dead-level;
## mouse look still adjusts freely from there within the usual clamp.
@export var default_camera_pitch_deg: float = -25.0
## Multiplies the spring arm's65c65n65i65u65e65 65e65g65h65 65165p65l65s65t65e65c65m65r65 65n65#65 65l65s65r65(65o65m65d65i65)65 65165p65s65e65 65t65f65r65h65r65b65c65.65@65x65o65t65v65r65c65m65r65_65o65m65 65l65a65 65 65.65
## How quickly the camera rig's position catches up to the player, in 1/seconds
## (exponential smoothing, frame-rate independent). Lower = more of a drone lag
## drifting into place; higher = tracks tighter. Not instant like a rigidly
## parented camera would be.
@export var camera_follow_speed: float = 5.0
## Same idea but for which way the rig is facing (yaw).
@export var camera_turn_speed: float = 4.0
## Same idea but for mouse-look pitch settling into place, instead of snapping.
@export var camera_pitch_speed: float = 8.0

## Movement is mass-invariant by design (buoyancy/swim forces scale with mass,
## so it cancels out in F=ma), but FluidBox's splash/wake strength scales with
## momentum = mass * speed. Keep this near a real body's mass or every push
## into the water gets clamped to its floor and barely shows.
@export var body_mass: float = 75.0

@export_group("Buoyancy")
## Fraction of the body resting below the surface at equilibrium. 0.5 = half
## submerged; smaller floats higher, larger sits deeper. This is the main knob.
## The body settles at
##     water_surface + body_half_height * (1.0 - 2.0 * target_submersion)
## so 0.5 puts the capsule's centre right on the waterline -- a whole metre of
## it above the surface, which reads as walking on water rather than swimming.
## 0.8 leaves about 0.4 m clear (head and shoulders) and is deep enough that
## the feet reach the shallow end's floor, so wading works there again.
## Keep it well under 1.0: at 1.0 the body is neutrally buoyant at every depth
## below the surface, with no waterline to settle back to.
@export_range(0.05, 1.0, 0.01) var target_submersion: float = 0.8
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
@export var momentum_in_shallow_end: float = 3.0
@export var max_momentum_by_walking: float = 3.5
@export var momentum_needed_to_swim: float = 5.0
## Momentum builds this fraction as fast when swimming forward (W); backward (S)
## builds at the normal rate. <1.0 makes forward slower.
@export var forward_swim_gain_mult: float = 0.5

## Floor a dodge raises the momentum stat to (see _dodge) -- not the actual
## push, which comes entirely from dodge_impulse below.
@export var dodge_momentum: float = 4.5
## Impulse (see apply_central_impulse) a dodge applies. This is the entire
## push -- actual distance depends on mass and normal water drag afterward,
## same as any other velocity change, not on any separate dodge duration.
@export var dodge_impulse := 900.0

## Seconds after a dodge before another one can trigger.
@export var dodge_cooldown: float = 1.0

@export_group("Jump")
## Only works standing in the shallow end -- a push off the pool floor, same
## as dodge. Spends all your momentum on launch; the more you had, the higher
## you go (see _jump).
@export var jump_power: float = 2
## Seconds after a jump before another one can trigger.
@export var jump_cooldown: float = 1.0

@export_group("")
# holy grail #1
# |
# V
@export var momentum: float = 0.0
# holy grail #2
# |
# V
@export var stamina: float = 100.0
# bullshit
# |
# V
@export var max_stamina: float = 100.0
@export var stamina_expended_dodge: float = 20.0 # can't dodge in the deep end
@export var stamina_in_shallow_end_per_second: float = 9.0
@export var stamina_expended_in_deep_end_per_second_tread: float = 2.5
@export var stamina_expended_in_deep_end_per_second_swim: float = 5.0
@export var stamina_expended_in_deep_end_per_second_glide: float = 0.1

var dir: Vector3 = Vector3.ZERO
var can_move: bool = true
@onready var gui: CanvasLayer = get_node("/root/Main/gui")
# Movement state: state of movement 👍
@export var movement_state: MovementState = MovementState.IDLE
var _ocean: Node = null
# Counts down after a dodge/jump until another one is allowed.
var _dodge_cooldown_timer: float = 0.0
var _jump_cooldown_timer: float = 0.0

@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _cam_pivot: Node3D = $CamPivot
@onready var _spring_arm: SpringArm3D = $CamPivot/SpringArm3D
# The scene's named floor meshes; see in_shallow_end(). shallow and
# transition both count as walkable; deep never does.
@onready var _shallow_floor: Node = get_node_or_null("/root/Main/shallow")
@onready var _transition_floor: Node = get_node_or_null("/root/Main/transition")
var _underwater_mat: ShaderMaterial

# Height above the body the camera rig hovers at, captured from the scene
# before we detach the rig from the body below.
var _cam_pivot_height: float = 0.0
var _gravity: float = 9.8
# Timestamp of the last physics tick we were backstroking (holding S while
# swim_key is held); see BACKSTROKE_FLIP_WINDOW.
var _last_backstroke_time: float = -1000.0

func _ready() -> void:
	# Free cursor, not locked to the window -- A/D turn the camera now (see
	# _physics_process), and water_power (press 1) aims wherever the cursor
	# actually is (see _mouse_aim_direction), which needs its on-screen
	# position, not a captured/hidden relative-motion pointer.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mass = body_mass
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	# Keep the capsule upright; buoyancy/torque shouldn't tip the player over.
	lock_rotation = true
	# Frictionless + non-bouncy: in the shallows the capsule's base rides right on
	# the pool floor, and default friction grabs it and stalls the swim. Movement
	# in water is slowed by drag, not by scraping the floor, so drop friction.
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0
	pm.bounce = 0.0
	physics_material_override = pm
	if ocean_path:
		_ocean = get_node_or_null(ocean_path)
	_underwater_mat = ShaderMaterial.new()
	_underwater_mat.shader = load("res://water/underwater.gdshader")

	# Detach the camera rig from the body so it can lag behind and drift into
	# place like a drone tracking its subject, instead of being welded 1:1 to
	# the body's every move (see _process for the actual catch-up lerp).
	# Deferred: reparenting synchronously from inside _ready() can leave the
	# node briefly reporting !is_inside_tree() to the current frame's process
	# pass; call_deferred runs it after the tree finishes settling instead.
	_cam_pivot_height = _cam_pivot.position.y
	call_deferred("_detach_camera_rig")
	_update_camera_pitch()

func _detach_camera_rig() -> void:
	if is_instance_valid(_cam_pivot):
		_cam_pivot.reparent(get_parent(), true)

func _process(delta: float) -> void:
	if not is_instance_valid(_cam_pivot) or not _cam_pivot.is_inside_tree():
		return
	# Position: drift the rig toward hovering above the body.
	var target_pos := global_position + Vector3.UP * _cam_pivot_height
	_cam_pivot.global_position = _cam_pivot.global_position.lerp(
		target_pos, 1.0 - exp(-camera_follow_speed * delta))
	# Yaw: catch up to which way the body is facing, same damped feel.
	var target_yaw := global_transform.basis.get_euler().y
	var current_yaw := _cam_pivot.global_transform.basis.get_euler().y
	var new_yaw := lerp_angle(current_yaw, target_yaw, 1.0 - exp(-camera_turn_speed * delta))
	_cam_pivot.global_rotation.y = new_yaw
	# Pitch: settle toward the baked overhead tilt instead of snapping to it --
	# fixed, not mouse-driven; the mouse is a pure aim pointer now.
	_camera.rotation.x = lerp_angle(
		_camera.rotation.x, deg_to_rad(default_camera_pitch_deg),
		1.0 - exp(-camera_pitch_speed * delta))

	_gui_change()


func _gui_change() -> void:
	gui.get_node("stamina_bar").value = stamina
	gui.get_node("momentum_bar").value = momentum

func _stamina_change(delta: float) -> void:
	var _shallow := in_shallow_end()
	if _shallow:
		stamina += delta * stamina_in_shallow_end_per_second
	else:
		if movement_state == MovementState.TREAD:
			stamina -= delta * stamina_expended_in_deep_end_per_second_tread
		elif movement_state == MovementState.SWIM:
			stamina -= delta * stamina_expended_in_deep_end_per_second_swim
		elif movement_state == MovementState.GLIDE:
			stamina -= delta * stamina_expended_in_deep_end_per_second_glide

func _input(event: InputEvent) -> void:
	var now := _time_since_start()
	detect_dodge(now, event)


func detect_dodge(now: float, event: InputEvent) -> void:
	if event.is_action_pressed("forward") \
		or event.is_action_pressed("back") \
		or event.is_action_pressed("swim_key"):
		return
	if event.is_action_pressed("left"):
		if now - last_a_press <= DODGE_DOUBLE_TAP_TIME:
			_dodge_left()

		last_a_press = now

	if event.is_action_pressed("right"):
		if now - last_d_press <= DODGE_DOUBLE_TAP_TIME:
			_dodge_right()

		last_d_press = now

func _dodge_left() -> void:
	_dodge(Vector3.LEFT)

func _dodge_right() -> void:
	_dodge(Vector3.RIGHT)

## A quick sideways burst triggered by double-tapping left/right (see _input).
## It's a push off the pool floor, not a swim stroke, so it costs a flat chunk
## of stamina and only works in the shallow end -- can't dodge in the deep end
## with nothing solid to push off of. Also gated by dodge_cooldown so it can't
## be chained back to back. Does exactly two things and nothing else: updates
## momentum/dir, and applies one impulse -- no separate duration/coast state,
## normal swim/walk/glide physics take over on the very next tick same as any
## other velocity change. local_dir is Vector3.LEFT/RIGHT in the body's own
## space, rotated to world space off the current facing (same convention
## _walk()/_swim() use for their own directions).
func _dodge(local_dir: Vector3) -> void:
	if DEBUG_IN_SHALLOW_WATER:
		print("dodge attempt: shallow=", in_shallow_end(), " submersion=", _submersion(),
				" stamina=", stamina, "/", stamina_expended_dodge,
				" cooldown=", _dodge_cooldown_timer,
				" wants_swim=", Input.is_action_pressed("swim_key"))
	if not in_shallow_end() or stamina < stamina_expended_dodge or _dodge_cooldown_timer > 0.0:
		return
	stamina -= stamina_expended_dodge
	_dodge_cooldown_timer = dodge_cooldown

	# 1. Momentum and direction. Clamped to momentum_needed_to_swim too, not
	# just dodge_momentum -- a dodge is a burst of real momentum, so swimming
	# right after one should never trip the swim_up wind-up
	# (_swim_up_animation_time gates that on momentum < momentum_needed_to_swim).
	dir = (transform.basis * local_dir).normalized()
	momentum = max(momentum, dodge_momentum, momentum_needed_to_swim)

	# 2. Impulse.
	var right := _camera.global_basis.x
	if local_dir == Vector3.LEFT:
		right = -right
	apply_central_impulse(right * dodge_impulse)

## A jump off the pool floor, triggered by the jump action. Only works
## standing in the shallow end (a push off solid ground, same reasoning as
## _dodge -- nothing to push off in open water), and gated by jump_cooldown so
## it can't be chained. Spends the *entire* momentum stat on launch -- the more
## you had going in, the higher you go -- so it also doubles as a hard reset:
## you land with none of your old speed left.
func _jump(shallow: bool) -> void:
	if not shallow or momentum <= 0.0 or _jump_cooldown_timer > 0.0:
		return
	_jump_cooldown_timer = jump_cooldown
	linear_velocity.y = momentum * jump_power
	momentum = 0.0
	movement_state = MovementState.JUMP

## Sets the camera's rotation.x straight to the baked overhead tilt, with no
## smoothing. Used once at startup so the camera doesn't visibly lerp in from
## rotation 0 on the first frame; every frame after that, _process settles it
## toward this same target smoothly instead. Fixed, not mouse-driven -- the
## mouse doesn't touch the camera at all now, it's a pure aim pointer.
func _update_camera_pitch() -> void:
	_camera.rotation.x = deg_to_rad(default_camera_pitch_deg)

## Turns the body (and the camera, which follows its yaw -- see _process)
## while A/D are held, at turn_speed rad/s. Replaces the old mouse-yaw and the
## old A/D strafe -- these keys steer now instead of sidestepping.
func _turn_from_input(delta: float) -> void:
	var turn := Input.get_axis("left", "right")
	if turn != 0.0:
		rotate_y(-turn * turn_speed * delta)

func _physics_process(delta: float) -> void:
	_turn_from_input(delta)

	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_jump_cooldown_timer = maxf(_jump_cooldown_timer - delta, 0.0)

	# Compute these once per tick; in_shallow_end() runs a raycast, so don't call
	# it (or _submersion) repeatedly below.
	var submersion := _submersion()
	var shallow := in_shallow_end()

	if Input.is_action_just_pressed("jump"):
		_jump(shallow)

	# Entry/exit splashes are handled by the water sim itself (it detects the
	# body crossing the surface and erupts a water crown scaled by the real
	# impact velocity + mass) -- so nothing to spawn from here.

	# Movement mode. You can swim wherever there's enough water by holding the swim
	# key. In the shallow end releasing it drops straight back to walking (no
	# gliding), since your feet can just touch down; in open water releasing it
	# glides as before.
	var wants_swim := Input.is_action_pressed("swim_key")

	if wants_swim and (shallow or submersion > 0.25):
		_swim(delta)
	elif shallow:
		_walk(delta)                # shallow end always walks unless actively swimming
	elif submersion > 0.25:
		_swim(delta)               # not holding swim in open water -> glides
	else:
		_walk(delta)

	# Gravity stays on everywhere; buoyancy grows smoothly with submersion so the
	# body has one stable resting waterline (no on/off flip that causes bobbing).
	# Standing in the shallow end (shallow or transition) without swimming is the
	# ONE case that skips it: there your feet should plant on the bottom rather
	# than float/fight it, so gravity and the floor collision take over.
	#
	# This MUST stay after the movement code above, not before it. Assigning
	# linear_velocity throws away any force applied earlier in the same tick --
	# the physics backend resets the force accumulator when body state is set
	# directly -- and the movement code assigns it in three places (_swim's
	# heading redirect, _stop_gliding, _jump). With buoyancy applied first, the
	# redirect (which switches on at momentum_needed_to_swim) silently ate it
	# every tick, so building momentum past ~5 in open water sank the player
	# with no buoyancy at all, whatever submersion said. Anything that applies
	# force belongs below the velocity writes, not above them.
	#
	# Out of water _apply_buoyancy is already a no-op -- submersion 0 zeroes both
	# its lift and its damping -- so it needs no guard of its own here.
	if not (shallow and not wants_swim):
		_apply_buoyancy(submersion)

	# Baseline momentum for wading in the shallows.
	if shallow:
		momentum = max(momentum_in_shallow_end, momentum)

	# Water power (press 1): send a wave skimming across the surface toward
	# wherever the mouse cursor is (horizontal only -- it rides the water, so
	# it starts at the surface height and can't be aimed up or down).
	if Input.is_action_just_pressed("water_power") and _ocean and _ocean.has_method("send_wave"):
		var aim := _mouse_aim_direction()
		var origin := global_position + aim * 1.0
		origin.y = _water_height()
		_ocean.send_wave(origin, aim, 1.0)

	# Wire the numbers up to the bar; see the exported stamina_* knobs above.
	_stamina_change(delta)
	stamina = clampf(stamina, 0.0, max_stamina)

## Fraction of the body below the water surface: 0 fully out, 1 fully under.
func _submersion() -> float:
	var bottom := global_position.y - body_half_height
	return clampf((_water_height() - bottom) / (2.0 * body_half_height), 0.0, 1.0)

## True when the player is standing on the bottom while still partly in the
## water -- the shallow end, where they should walk rather than swim, dodge,
## or jump, and where buoyancy shouldn't fight standing still. The scene's
## "shallow" and "transition" floor meshes both count; "deep" never does.
func in_shallow_end() -> bool:
	var water_y := _water_height()
	# Not in the water at all -- nothing to be shallow in.
	if water_y <= global_position.y - body_half_height:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * ground_probe)
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return false
	var collider = result.get("collider")
	if not (collider is Node):
		return false
	if not ((_shallow_floor and (collider == _shallow_floor or _shallow_floor.is_ancestor_of(collider))) \
			or (_transition_floor and (collider == _transition_floor or _transition_floor.is_ancestor_of(collider)))):
		return false
	# Which mesh is underfoot isn't enough on its own: "transition" is one long
	# ramp running from the shallow end all the way down to the deep floor, so
	# hitting it says nothing about how deep the water is there. Standing only
	# makes sense where the bottom is within a body height of the surface --
	# any deeper and the water is over your head, which is the deep end no
	# matter which mesh happens to be below you. Without this the ramp reads as
	# shallow at every depth, and since _physics_process skips buoyancy in the
	# shallows, gravity drags you down with nothing opposing it (water drag is
	# horizontal only) -- and the ramp stays under you the whole way down, so
	# the ray keeps hitting it and you never get buoyancy back.
	return water_y - result.position.y <= 2.0 * body_half_height

func _swim_up_animation_time() -> float:
	if momentum >= momentum_needed_to_swim:
		return 0.0

	var t = momentum / momentum_needed_to_swim
	return lerp(0.5, 1.5, t)

## World-space height of the water surface, used for submersion and so for
## buoyancy.
##
## Deliberately the *undisturbed* surface, not the live wave height under the
## player. Lift is proportional to submersion, so anything that dents the
## surface reading weakens it -- and the deepest dent in this pool is the one
## the player carves under themselves: the fluid sim digs a depression at every
## moving body, every tick (FluidBox._continuous_interaction), right where a
## live reading would sample. That made swimming fast measure the bottom of
## your own wake, and gravity won. Reading the rest surface takes the sim out
## of the buoyancy loop entirely, so no wake, trench or splash can sink you.
## The cost is that the player no longer rides the swell up and down, which is
## a fair trade for never being dragged under by their own wash.
func _water_height() -> float:
	if _ocean:
		if _ocean.has_method("get_rest_height"):
			return _ocean.get_rest_height()
		if _ocean.has_method("get_height_at"):
			return _ocean.get_height_at(global_position)
	return 0.0

## Horizontal direction from the player toward wherever the mouse cursor is
## pointing, for aiming water_power. Casts a ray from the camera through the
## cursor's on-screen position and intersects it with the water's (flat)
## surface plane; falls back to facing forward if the cursor isn't aimed at
## the water at all (e.g. pointed above the horizon, so the ray never reaches
## the plane, or the ray points away from it).
func _mouse_aim_direction() -> Vector3:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)
	var plane_y := _water_height()

	if absf(ray_dir.y) > 0.0001:
		var t := (plane_y - ray_origin.y) / ray_dir.y
		if t > 0.0:
			var hit := ray_origin + ray_dir * t
			var aim := Vector3(hit.x - global_position.x, 0.0, hit.z - global_position.z)
			if aim.length() > 0.01:
				return aim.normalized()

	var forward := -transform.basis.z
	forward.y = 0.0
	return forward.normalized()

## Gets time in seconds since started.
func _time_since_start() -> float:
	return Time.get_ticks_msec() / 1000.0

func _walk(delta: float) -> void:
	can_move = true
	# Forward/back only -- left/right now turn instead of strafing (see
	# _turn_from_input), same as swimming.
	var input_dir := Vector2(0.0, Input.get_axis("forward", "back"))
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# walk while moving, idle when standing still
	movement_state = MovementState.WALK if direction else MovementState.IDLE

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
	var in_shallow := in_shallow_end()
	if DEBUG_IN_SHALLOW_WATER:
		print("in_shallow: ", in_shallow)
	if not Input.is_action_pressed("swim_key"):
		_glide(delta)
		return
	# Actively swimming re-enables movement after a tread stopped it, so the
	# player isn't permanently frozen once momentum drains to zero.
	can_move = true
	# Momentum (0.0 -> 1.0)
	var t := momentum / max_momentum

	# Intentional swim thrust direction (horizontal only). Forward/back only --
	# left/right turn instead of strafing (see _turn_from_input).
	var input_dir := Vector2(0.0, Input.get_axis("forward", "back"))
	if Input.is_action_pressed("back"):
		_last_backstroke_time = _time_since_start()
	# Switch a backstroke (S) straight into a forward stroke (W) without releasing
	# the swim key: whip around 180 and keep the momentum, so you don't have to
	# let go and coast to turn around. Uses a grace window (BACKSTROKE_FLIP_WINDOW)
	# rather than requiring S and W to overlap on the exact same physics tick --
	# that overlap is basically impossible to land on purpose by hand.
	if (Input.is_action_just_pressed("forward")
			and _time_since_start() - _last_backstroke_time <= BACKSTROKE_FLIP_WINDOW):
		rotate_y(PI)

	# Horizontal only, off the body's own facing -- same as _walk(). Not the
	# camera's: the camera rig now lags behind (drone follow, see _process),
	# and steering off a laggy basis would make turns feel mushy. Camera pitch
	# never factored in here either way: looking up or down must never change
	# which way the player swims. Depth is buoyancy's job.
	dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y))

	# With enough momentum already banked, a stroke should just move --
	# instantly, not ease in through the usual drag-vs-thrust tug of war.
	# Without that, changing heading while carrying residual velocity from
	# something else (a dodge, a glide) reads as a dead pause: drag cancels
	# the old heading while thrust rebuilds the new one from near scratch,
	# even though there's already plenty of momentum to be moving right now.
	# Redirects the existing horizontal speed onto the new heading instead of
	# decaying it and rebuilding it from zero.
	if momentum >= momentum_needed_to_swim and dir.length() > 0.01:
		var speed := Vector2(linear_velocity.x, linear_velocity.z).length()
		var redirected := dir.normalized() * speed
		linear_velocity.x = redirected.x
		linear_velocity.z = redirected.z

	# The wake, ripples and bow wave come purely from the fluid sim reacting to
	# the body moving through it (FluidBox tracks our real velocity + mass and
	# drives the wave equation) -- no scripted splashes here, so what you see is
	# the physics, not a canned effect.

	# Build momentum only while actually pushing forward/back -- holding
	# swim_key alone with no W/S shouldn't quietly keep building it up.
	# Standing still bleeds it off instead, same as _walk() does when you
	# stop moving.
	if input_dir.y != 0.0:
		# During the swim-up wind-up, pace it so momentum reaches the swim
		# threshold over _swim_up_animation_time() seconds; once swimming,
		# keep building toward max the usual way (fast at first, slow near
		# max). Forward (W, input_dir.y < 0) builds momentum slower; backward
		# (S) is normal.
		var gain_scale := forward_swim_gain_mult if input_dir.y < 0.0 else 1.0
		var swim_up_time := _swim_up_animation_time()
		if swim_up_time > 0.0:
			momentum += momentum_needed_to_swim / swim_up_time * delta * gain_scale
		else:
			momentum += SWIM_GAIN * pow(1.0 - t, 2.0) * delta * gain_scale
		momentum = min(momentum, max_momentum)
	else:
		momentum = move_toward(momentum, 0.0, SWIM_GAIN * delta)

	# swim_up is the wind-up phase spent building the momentum needed to swim
	# (see _swim_up_animation_time); once past the threshold it's a full swim.
	movement_state = MovementState.SWIM if momentum >= momentum_needed_to_swim else MovementState.SWIM_UP

	# Drag + thrust, shared with gliding so both top out at the same speed.
	_apply_swim_motion(dir, t)

func _glide(delta: float) -> void:
	# go along path, conserving momentum but not gaining any
	# basically like swimming but lose momentum
	# if momentum reaches zero, stop gliding and tread
	# Coast along the last heading flattened to horizontal, so a glide doesn't
	# drift up or down from wherever the camera was pointing when you let go.
	var glide_dir := Vector3(dir.x, 0.0, dir.z)

	# Press a movement key to cancel the glide, or stop dead if we hit a wall.
	# left/right aren't movement keys anymore (they just turn now, see
	# _turn_from_input) -- and a dodge is triggered by double-tapping one of
	# them, so treating them as cancel input here was zeroing out the dodge's
	# impulse the instant it landed.
	if (Input.is_action_just_pressed("forward")
			or Input.is_action_just_pressed("back")
			or _wall_ahead(glide_dir)):
		_stop_gliding()
		return

	if momentum > 0.0:
		movement_state = MovementState.GLIDE
		momentum -= SWIM_GAIN * delta
		var t = momentum / max_momentum
		_apply_swim_motion(glide_dir, t)
	else:
		momentum = 0.0
		_tread()

## Water drag opposing whatever the body's current velocity actually is, for
## momentum fraction `t`. Split out from _apply_swim_motion so a dodge (see
## _physics_process) can stay under drag the whole time instead of coasting
## undamped and then taking the full correction as a lump the instant it ends.
func _apply_water_drag(t: float) -> void:
	var v := linear_velocity
	var drag: float = lerp(water_linear_drag * 1.5, water_linear_drag * 0.5, t)
	_apply_central_force(Vector3(-v.x, 0.0, -v.z) * drag * mass)

## Water drag plus forward thrust for the given momentum fraction `t` and move
## direction. Shared by swimming and gliding so both settle at the same speed
## for the same momentum -- gliding no longer coasts faster than swimming.
func _apply_swim_motion(move_dir: Vector3, t: float) -> void:
	_apply_water_drag(t)
	if move_dir.length() > 0.01:
		var swim_force: float = lerp(swim_speed * 0.5, swim_speed * 1.5, t)
		_apply_central_force(move_dir.normalized() * swim_force * mass)

## True when a genuinely vertical surface is within `wall_probe` ahead along
## `direction` -- a wall to stop a glide against, not the shallow end's rising
## floor. Distinguished by the hit surface's normal: a wall's points mostly
## sideways (normal.y near 0), while a floor/ramp's points mostly up (normal.y
## near 1). Without this check, swimming up the shallow end's slope reads as
## hitting a wall and kills momentum on every such contact.
func _wall_ahead(direction: Vector3) -> bool:
	if direction.length() < 0.01:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + direction.normalized() * wall_probe)
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return false
	var normal: Vector3 = result.normal
	return absf(normal.y) < 0.5

## Halt a glide: kill horizontal speed and drop back to treading.
func _stop_gliding() -> void:
	linear_velocity.x = 0.0
	linear_velocity.z = 0.0
	_tread()

func _tread() -> void:
	movement_state = MovementState.TREAD
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
	# Damping scales with submersion alongside the lift, so out of the water this
	# whole function contributes exactly nothing and needs no caller-side guard
	# (see _physics_process). Water resists a body moving through it in
	# proportion to how much of the body is actually in the water; air shouldn't
	# brake a jump at all.
	var accel := lift_accel - v.y * damping * submersion
	# Buoyancy is passive physics -- apply it directly, never gated by can_move,
	# or the player would sink whenever movement is disabled (e.g. after treading).
	apply_central_force(Vector3.UP * accel * mass)

func _apply_central_force(force: Vector3) -> void:
	if can_move:
		apply_central_force(force)
