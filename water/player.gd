# scene properties and rpc entry points stay on the player
extends RigidBody3D

const Controller = preload("res://water/player/controller.gd")
var using_controller := false
var controller_angles := Vector2.ZERO
var controller_dodge_taps: Dictionary = {}
var _jump_spent := false

const Types = preload("res://water/player/types.gd")
const Appearance = preload("res://water/player/appearance.gd")
const Camera = preload("res://water/player/camera.gd")
const Movement = preload("res://water/player/movement.gd")
const Combat = preload("res://water/player/combat.gd")
const Vitality = preload("res://water/player/vitality.gd")

const MovementState = Types.MovementState

const Team = Types.Team

# almost a copy of the movement state enum but with dodge left and right
const AnimationState = Types.AnimationState
const WaterMove = Types.WaterMove

# define this at the top of your script
const ANIM_MAP = Types.ANIM_MAP

const SWIM_GAIN: float = 10.0
# fallback clip length for swim_up only used if the real length cant be read
const SWIM_UP_ANIMATION_BASE_TIME := 0.5
# bounds on the swim_up playback rate without a ceiling the last frames blur as
const _SWIM_UP_MIN_SPEED := 0.25
const _SWIM_UP_MAX_SPEED := 4.0
const DODGE_DOUBLE_TAP_TIME := 0.25
const CONTROL_CAMERA := true
const ANIMATE_PLAYER := true
const DEBUG_IN_SHALLOW_WATER: bool = false
const _REMOTE_UPDATE_INTERVAL := 0.1
const _REMOTE_SNAP_DISTANCE := 12.0

# normal vs lifeguard numbers for is_lifeguards stat buffs see _apply_lifeguard_loadout below both sides are
const _NORMAL_WATER_POWER_DAMAGE_MAX := 30.0
const _NORMAL_WATER_ATTACK_DAMAGE_MAX := 65.0
const _NORMAL_MOMENTUM_GAIN_MULT := 1.0
const _NORMAL_MOMENTUM_LOSS_MULT := 1.0
const _NORMAL_WATER_WALL_BLOCK_REDUCTION := 0.5 # halves an incoming hit while blocking

const _LIFEGUARD_WATER_POWER_DAMAGE_MAX := 60.0
const _LIFEGUARD_WATER_ATTACK_DAMAGE_MAX := 80.0
const _LIFEGUARD_MOMENTUM_GAIN_MULT := 1.3
const _LIFEGUARD_MOMENTUM_LOSS_MULT := 0.5
const _LIFEGUARD_WATER_WALL_BLOCK_REDUCTION := 0.1 # the kickboard block 90 of the hit never lands

const _CHARACTER_MESH := preload("res://mesh/character.glb")
const _LIFEGUARD_MESH := preload("res://mesh/lifeguard.glb")
const _REVIVE_PROMPT := preload("res://water/revive_prompt.tscn")
const _NAMEPLATE := preload("res://water/nameplate.tscn")

# team kit colours both rigs mesh character glb mesh lifeguard glb are textured off
const _TEAM_COLORS: Dictionary = {
	Team.RED: Color("d92d2d"),
	Team.BLUE: Color("2d6bd9"),
}
# how close to white a texel has to be to count as kit the
const _TEAM_WHITE_CUTOFF = Appearance._TEAM_WHITE_CUTOFF

# movement state clip names see anim_map that should genuinely loop loop_linear on mesh character
const _CHARACTER_LOOP_ANIMS: Array[String] = ["idle", "tread", "swim", "glide", "walk", "jump"]

# grace window for the backstroke forward stroke flip how long after last holding s
const BACKSTROKE_FLIP_WINDOW := 0.25
var last_a_press := -1000.0
var last_d_press := -1000.0


# top movement speed in m s reached at full momentum momentum scales speed from
@export var swim_speed: float = 12.0
# radians second the body and camera which follows its yaw turns while holding a
@export var turn_speed: float = 2.5

@export_group("Camera")
# camera starts pitched down by this many degrees so the rig already raised above
@export var default_camera_pitch_deg: float = -36.0
# how high above the player campivot hovers in metres baked into water player tscns
@export var camera_hover_height: float = 3.2
# how quickly the camera rigs position catches up to the player in 1 seconds
@export var camera_follow_speed: float = 5.0
# same idea but for which way the rig is facing yaw
@export var camera_turn_speed: float = 4.0
# same idea but for mouse look pitch settling into place instead of snapping
@export var camera_pitch_speed: float = 8.0

# whether a d turning ramps up the longer the key is held instead of
@export var exponential_turn_sensitivity: bool = false
# seconds of continuous a d hold to reach 95 of full turn_speed when exponential_turn_sensitivity
@export var turn_ramp_time: float = 0.6

# movement is mass invariant by design buoyancy swim forces scale with mass so it
@export var body_mass: float = 75.0

@export_group("Buoyancy")
# fraction of the body resting below the surface at equilibrium 0 5 half submerged
@export_range(0.05, 1.0, 0.01) var target_submersion: float = 0.8
# damping ratio for the vertical bob 1 0 critically damped settles fast no overshoot
@export var damping_ratio: float = 1.1
# resistance applied to movement while submerged
@export var water_linear_drag: float = 3.0
# half the bodys height used to measure how much of it is under water
@export var body_half_height: float = 1.0
# downward probe length used to detect ground for walking
@export var ground_probe: float = 1.1
# forward probe length used to detect a wall ahead while gliding
@export var wall_probe: float = 0.7
@export var ocean_path: NodePath
# off for a purely decorative player one dropped into a scene e g the
@export var take_over_camera: bool = true
# momentum for how fast the player moves and later attacks and combos and shit
@export var max_momentum: float = 10.0
@export var momentum_in_shallow_end: float = 3.0
@export var max_momentum_by_walking: float = 3.5
@export var momentum_needed_to_swim: float = 5.0
# momentum builds this fraction as fast when swimming forward w backward s builds at
@export var forward_swim_gain_mult: float = 0.5

# floor a dodge raises the momentum stat to see _dodge not the actual push
@export var dodge_momentum: float = 4.5
# impulse see apply_central_impulse a dodge applies this is the entire push actual distance depends
@export var dodge_impulse := 900.0

# seconds after a dodge before another one can trigger
@export var dodge_cooldown: float = 1.0

@export_group("Jump")
# only works standing in the shallow end a push off the pool floor same
@export var jump_speed: float = 16.0
@export var arcade_jump_mult: float = 2.0
@export var cube_jump_speed: float = 7.0
@export var cube_jump_range: float = 3.0
# how sharply momentum stops paying off the launch scales with momentum max_momentum jump_momentum_exponent so
@export_range(0.1, 1.0, 0.01) var jump_momentum_exponent: float = 0.5
# seconds after a jump before another one can trigger
@export var jump_cooldown: float = 1.0
@export var jump_cancel_momentum: float = 8.0
@export var jump_cancel_stamina_cost: float = 10.0

@export_group("Blackout")
# fallback for how long the eyelids take to fall shut normally the close is
@export var blackout_time: float = 4.5
# seconds the eyelids take to fly back open on revive much shorter than the
@export var eyelid_open_time: float = 0.22
# how much of the tank revive hands back as a fraction of max_stamina must
@export_range(0.05, 1.0, 0.01) var revive_stamina_fraction: float = 0.5
# camera jolt on revive in camera offset units tiny by design 0 06 reads
@export var revive_shake_strength: float = 0.06
# seconds that jolt takes to decay to nothing
@export var revive_shake_time: float = 0.25
# how close a lifeguard has to be to pick a downed teammate up in
@export var revive_range: float = 3.0

@export_group("")
# holy grail 1 v
@export var momentum: float = 0.0
# holy grail 2 v
@export var stamina: float = 100.0
# bullshit v
@export var max_stamina: float = 100.0
@export var max_arcade_stamina: float = 200.0
@export var balance_mult: float = 0.5
@export var stamina_expended_dodge: float = 20.0 # cant dodge in the deep end
@export var stamina_in_shallow_end_per_second: float = 9.0 * balance_mult
@export var stamina_expended_in_deep_end_per_second_tread: float = 2.5 * balance_mult
@export var stamina_expended_in_deep_end_per_second_swim: float = 5.0 * balance_mult
@export var stamina_expended_in_deep_end_per_second_glide: float = 0.1 * balance_mult
@export var stamina_recovery_out_of_water_per_second: float = 9.0 * balance_mult
@export var water_power_stamina_cost: float = 10.0 * balance_mult
@export var water_attack_stamina_cost: float = 5.0 * balance_mult
@export var water_pelt_stamina_cost: float = 5.0
@export var water_counter_stamina_cost: float = 50.0
@export var water_wall_stamina_cost_per_second: float = 20.0 * balance_mult

# seconds after casting before that same move can fire again same reasoning as dodge_cooldown
@export var water_power_cooldown: float = 0.6
@export var water_attack_cooldown: float = 0.4
@export var water_pelt_cooldown: float = 0.45

# how much extra water_power strength banked momentum buys on top of the baseline 1
@export var water_power_momentum_bonus: float = 1.5
# diminishing returns on the momentum bonus same idiom and same reasoning as jump_momentum_exponent above
@export_range(0.1, 1.0, 0.01) var water_power_momentum_exponent: float = 0.6

@export_group("Teams")
# which side this body plays for drives the bodys colour see _apply_team_colors every white
@export var team: Team = Team.RED:
	set(value):
		if team == value:
			return
		team = value
		# spawn properties arrive before the mesh is ready
		if is_node_ready():
			_apply_team_colors()

@export_group("Lifeguard")
# off duty by default on swaps blockbench_export for mesh lifeguard glb same rig animations
@export var is_lifeguard: bool = false:
	set(value):
		if is_lifeguard == value:
			return
		is_lifeguard = value
		if is_node_ready():
			_apply_lifeguard_loadout()

# damage range at strength 1 for a hit that lands see ocean_fluid_bridge gds _apply_hit_damage
@export var water_power_damage_min: float = 8.0
@export var water_power_damage_max: float = _NORMAL_WATER_POWER_DAMAGE_MAX
@export var water_attack_damage_min: float = 35.0
@export var water_attack_damage_max: float = _NORMAL_WATER_ATTACK_DAMAGE_MAX

# multiplies momentum gained while swimming and momentum lost per second while idling in open
@export var momentum_gain_mult: float = _NORMAL_MOMENTUM_GAIN_MULT
@export var momentum_loss_mult: float = _NORMAL_MOMENTUM_LOSS_MULT

# fraction of an incoming hit that still gets through while holding a water wall
@export var water_wall_block_reduction: float = _NORMAL_WATER_WALL_BLOCK_REDUCTION
@export_group("") # closes lifeguard movement_state etc below are ungrouped again

var dir: Vector3 = Vector3.ZERO
var can_move: bool = true
# get_node_or_null not get_node a decorative player dropped into a scene with no hud see
@onready var gui: CanvasLayer = get_node_or_null("/root/Main/gui")
# movement state state of movement
@export var movement_state: MovementState = MovementState.IDLE
var _ocean: Node = null
# counts down after a dodge jump until another one is allowed
var _dodge_cooldown_timer: float = 0.0
var _jump_cooldown_timer: float = 0.0
var _jump_cancel_available := false
# counts down after casting water_power water_attack until that same move can fire again see
var _water_power_cooldown_timer: float = 0.0
var _water_attack_cooldown_timer: float = 0.0
var _water_pelt_cooldown_timer: float = 0.0
var _pelt_sequence := 0
# how long a d has been continuously held resets the instant its released only
var _turn_hold_time: float = 0.0

# water_power water_attack are authored to hold on their last frame this tracks the movement_state
var _action_anim_lock_movement_state: int = -1
# which animationstate play_anim last told the animationplayer to play tracked independently of what the
var _movement_anim_state: int = -1
# water_wall loops for as long as the key is held this just tells _anim_change
var _wall_anim_active: bool = false
# true while the water wall is up take_stamina_damage halves incoming damage while this is
var _water_wall_up: bool = false
var _water_counter_timer := 0.0
# the peer this body belongs to read off the node name in _enter_tree 0
var _owner_peer: int = 0
# this windows floating r revive tag built on demand see _ensure_revive_prompt
var _revive_prompt: Node = null
# this windows floating teammate name tags peer id nameplate instance see _update_nameplates
var _nameplates: Dictionary = {}
# the stroke scaling _swim last built momentum with direction times the lifeguard buff cached
var _swim_gain_scale: float = 1.0
# set while the round hasnt begun bodies are spawned on their teams side of
var movement_locked: bool = false

# keep received transforms separate so late joins get the latest network position
var _remote_transform := Transform3D.IDENTITY
var _remote_from := Transform3D.IDENTITY
var _remote_blend := 1.0
var _has_remote_transform := false
var replicated_transform: Transform3D:
	get:
		return _remote_transform if _has_remote_transform and not _is_local() else transform
	set(value):
		var snap := not is_node_ready() or _is_local() or not _has_remote_transform \
			or position.distance_to(value.origin) > _REMOTE_SNAP_DISTANCE
		if not snap and value.is_equal_approx(_remote_transform):
			return
		_remote_from = transform
		_remote_blend = 1.0 if snap else 0.0
		_remote_transform = value
		_has_remote_transform = true
		if snap:
			transform = value
			reset_physics_interpolation()

@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _cam_pivot: Node3D = $CamPivot
# get_node_or_null see the comment on gui above same failure mode
@onready var _muffled_player: AudioStreamPlayer = get_node_or_null("/root/Main/muffled_player")
# the scenes named floor meshes see in_shallow_end shallow and transition both count as walkable
@onready var _shallow_floor: Node = get_node_or_null("/root/Main/shallow")
@onready var _transition_floor: Node = get_node_or_null("/root/Main/transition")
@onready var _eyelid: ColorRect = get_node_or_null("/root/Main/gui/eyelid")
@onready var _anim_player: AnimationPlayer = get_node_or_null("blockbench_export/AnimationPlayer")
var _underwater_mat: ShaderMaterial

# height above the body the camera rig hovers at captured from the scene before
var _cam_pivot_height: float = 0.0
var _gravity: float = 9.8
# timestamp of the last physics tick we were backstroking holding s while swim_key is
var _last_backstroke_time: float = -1000.0
# latched by _death once stamina runs out see there gates input and the whole
var _unconscious: bool = false
var replicated_unconscious: bool:
	get:
		return _unconscious
	set(value):
		if not is_node_ready():
			_unconscious = value
		elif value != _unconscious:
			if value:
				net_death()
			else:
				net_revive()

var _received_animation: Array = []
var replicated_animation: Array:
	get:
		if not is_node_ready() or not _anim_player or _anim_player.assigned_animation.is_empty():
			return _received_animation
		return [_anim_player.assigned_animation, _anim_player.current_animation_position,
			_anim_player.speed_scale, _anim_player.is_playing()]
	set(value):
		_received_animation = value
		if is_node_ready() and not _is_local():
			_apply_replicated_animation()

var _wall_state: Array = []
var vr_arms: Node3D
var _received_vr_pose: Array = []
var replicated_vr_pose: Array:
	get:
		return vr_arms.pose if is_instance_valid(vr_arms) else _received_vr_pose
	set(value):
		if preload("res://water/player/vr_arms.gd").valid_pose(value):
			_received_vr_pose = value
			if is_instance_valid(vr_arms):
				vr_arms.pose = value

var replicated_wall: Array:
	get:
		return _wall_state
	set(value):
		_wall_state = value
		if is_node_ready() and not _is_local():
			if value.is_empty():
				net_water_wall_stop()
			else:
				net_water_wall(value[0], value[1], value[2])
# the eyelid tween kept so revive can kill a close thats still in flight
var _eyelid_tween: Tween = null
# camera shake state see _shake_change
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_strength: float = 0.0

# the nodes name is the peer id that owns this body net gd names
func _enter_tree() -> void:
	_owner_peer = str(name).to_int()
	var spawn_sync := get_node_or_null("SpawnSynchronizer")
	# 0 means the name isnt a peer id at all the scene opened on
	if _owner_peer > 0:
		set_multiplayer_authority(_owner_peer)
		# the host controls spawning and roles while each player controls their movement
		if spawn_sync:
			spawn_sync.set_multiplayer_authority(1)
	else:
		# a body outside the real networked spawn system entirely e g menu tscns menuplayer
		var sync := get_node_or_null("MultiplayerSynchronizer")
		if sync:
			sync.queue_free()
		if spawn_sync:
			spawn_sync.queue_free()
		var vr_sync := get_node_or_null("VRPoseSynchronizer")
		if vr_sync:
			vr_sync.queue_free()
	# lets net gd find the local player without assuming where in the tree it
	add_to_group("player")

# a raised water wall belongs to the ocean node not to this one so
func _exit_tree() -> void:
	if _ocean and _ocean.has_method("stop_water_wall"):
		_ocean.stop_water_wall(self)

# true when this body is the one this game window drives reads input owns
func _is_local() -> bool:
	return is_multiplayer_authority()

func max_stamina_per_mode(game_mode: Net.GameMode) -> float:
	if game_mode == Net.GameMode.ARCADE:
		return max_arcade_stamina
	else:
		return max_stamina

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON if _is_local() else Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mass = body_mass
	max_contacts_reported = maxi(max_contacts_reported, 8)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	# keep the capsule upright buoyancy torque shouldnt tip the player over
	lock_rotation = true
	# frictionless non bouncy in the shallows the capsules base rides right on the pool
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0
	pm.bounce = 0.0
	physics_material_override = pm
	if ocean_path:
		_ocean = get_node_or_null(ocean_path)

	# what side were on if the roster already knows the host assigns teams and
	if _owner_peer > 0:
		var assigned := Net.team_of(_owner_peer)
		if assigned >= 0:
			team = assigned

	# kickboard rig stat buffs if is_lifeguard was baked on for this instance deferred to
	_apply_lifeguard_loadout()
	if _owner_peer > 0:
		vr_arms = preload("res://water/player/vr_arms.gd").new()
		vr_arms.name = "TrackedArms"
		vr_arms.pose = _received_vr_pose
		add_child(vr_arms)

	# everything past here belongs to whoever is playing in this window the one cursor
	if not _is_local():
		_setup_remote_body()
		return

	stamina = max_stamina_per_mode(Net.game_mode)

	# saved camera turning settings before any of it gets used below camera_hover_height in particular
	Settings.apply_to(self)

	# free cursor not locked to the window a d turn the camera now see
	if take_over_camera:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_camera.current = true
	else:
		# not just skip claiming it actively give it up camera3d auto promotes itself to
		_camera.current = false

	# place ourselves rather than waiting to be told where we are the host sets
	if _owner_peer > 0:
		position = Net.spawn_position(_owner_peer)
	reset_physics_interpolation()

	# drive the bars ranges from the real stat maxima theyre authored in the scene
	if gui:
		var stamina_bar: Range = gui.get_node_or_null("stamina_bar")
		if stamina_bar:
			stamina_bar.max_value = max_stamina_per_mode(Net.game_mode)
		var momentum_bar: Range = gui.get_node_or_null("momentum_bar")
		if momentum_bar:
			momentum_bar.max_value = max_momentum

	_underwater_mat = ShaderMaterial.new()
	_underwater_mat.shader = load("res://water/underwater.gdshader")

	# detach the camera rig from the body so it can lag behind and drift
	_cam_pivot_height = camera_hover_height
	call_deferred("_detach_camera_rig")
	_update_camera_pitch()

func _apply_lifeguard_loadout() -> void:
	Appearance._apply_lifeguard_loadout(self)

func _apply_mesh_for_lifeguard() -> void:
	Appearance._apply_mesh_for_lifeguard(self)


func _apply_team_colors() -> void:
	Appearance._apply_team_colors(self)


func _mesh_instances_in(node: Node) -> Array[MeshInstance3D]:
	return Appearance._mesh_instances_in(self, node)


static func _tinted_texture(source: Texture2D, color: Color) -> ImageTexture:
	return Appearance._tinted_texture(source, color)

func _fix_animation_loop_modes() -> void:
	Appearance._fix_animation_loop_modes(self)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	Movement._integrate_forces(self, state)


# remote bodies follow their owners
func _setup_remote_body() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	if is_instance_valid(_cam_pivot):
		_cam_pivot.queue_free()
	if not _wall_state.is_empty():
		net_water_wall(_wall_state[0], _wall_state[1], _wall_state[2])
	if not _received_animation.is_empty():
		_apply_replicated_animation()
	elif _unconscious and _anim_player.has_animation("death"):
		_anim_player.play("death")
		_anim_player.seek(_anim_player.get_animation("death").length, true)


func _apply_replicated_animation() -> void:
	Appearance._apply_replicated_animation(self)

func anim_name_to_string(anim_name: AnimationState) -> String:
	return Appearance.anim_name_to_string(self, anim_name)

func play_anim(anim_state: AnimationState) -> void:
	Appearance.play_anim(self, anim_state)

func _play_water_action_anim(anim_name: String) -> void:
	Appearance._play_water_action_anim(self, anim_name)

func _play_water_wall_anim() -> void:
	Appearance._play_water_wall_anim(self)

func _stop_water_wall_anim() -> void:
	Appearance._stop_water_wall_anim(self)

func _detach_camera_rig() -> void:
	Camera._detach_camera_rig(self)

func _process(delta: float) -> void:
	# remote animations follow the owners clip and playback time
	if ANIMATE_PLAYER and (_is_local() or not Net.is_online()):
		_anim_change()

	# the camera the cursor and the shake are per window so they only make
	if not _is_local():
		if not Net.arcade.controls(self):
			_interpolate_remote_movement(delta)
		return

	if CONTROL_CAMERA:
		_camera_pivot_change(delta)

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_shake_change(delta)
	_update_revive_prompt()
	_update_nameplates()


func _interpolate_remote_movement(delta: float) -> void:
	if _is_local() or not _has_remote_transform:
		return
	_remote_blend = minf(_remote_blend + delta / _REMOTE_UPDATE_INTERVAL, 1.0)
	transform = _remote_from.interpolate_with(_remote_transform, _remote_blend)

func _shake_change(delta: float) -> void:
	Camera._shake_change(self, delta)

func shake_camera(strength: float, duration: float) -> void:
	Camera.shake_camera(self, strength, duration)

func _anim_change() -> void:
	Appearance._anim_change(self)


func _cast_water_move(kind: WaterMove, origin: Vector3, aim: Vector3, strength: float) -> void:
	Combat._cast_water_move(self, kind, origin, aim, strength)

@rpc("authority", "call_local", "reliable")
func net_cast_water_move(kind: WaterMove, origin: Vector3, aim: Vector3, strength: float,
		hit: Dictionary = {}) -> void:
	Combat.net_cast_water_move(self, kind, origin, aim, strength, hit)


func _try_water_counter() -> bool:
	return Combat._try_water_counter(self)


func _update_water_counter(delta: float) -> void:
	Combat._update_water_counter(self, delta)


func _try_water_pelt(hand := -1) -> bool:
	return Combat._try_water_pelt(self, hand)

func _cast_water_wall(origin: Vector3, aim: Vector3, strength: float) -> void:
	Combat._cast_water_wall(self, origin, aim, strength)

@rpc("any_peer", "call_local", "unreliable")
func net_water_wall(origin: Vector3, aim: Vector3, strength: float) -> void:
	Combat.net_water_wall(self, origin, aim, strength)

func _cast_water_wall_stop() -> void:
	Combat._cast_water_wall_stop(self)

@rpc("any_peer", "call_local", "reliable")
func net_water_wall_stop() -> void:
	Combat.net_water_wall_stop(self)

# knockback applied where this bodys physics actually run called by ocean_fluid_bridges _knockback via _send_to_owner
@rpc("any_peer", "reliable")
func net_apply_impulse(impulse: Vector3) -> void:
	if _is_local():
		apply_central_impulse(impulse)


func _camera_pivot_change(delta: float) -> void:
	Camera._camera_pivot_change(self, delta)


func _camera_look_angles(target: Node3D, fallback: Vector2) -> Vector2:
	return Camera._camera_look_angles(self, target, fallback)


func _scoreboard_look_node() -> Node3D:
	return Camera._scoreboard_look_node(self)

func _gui_change() -> void:
	Camera._gui_change(self)

func _stamina_change(delta: float) -> void:
	Vitality._stamina_change(self, delta)

@rpc("any_peer", "reliable")
func take_stamina_damage(amount: float) -> void:
	Vitality.take_stamina_damage(self, amount)

func _input(event: InputEvent) -> void:
	# keystrokes in this window drive this windows player and nobody elses without this one
	if not _is_local():
		return
	Controller.track(self, event)
	if Net.input_blocked_by_menu():
		return
	if Net.is_spectating():
		return
	if _unconscious:
		return
	# nothing lands before the countdown finishes not moves not the revive key not the
	if movement_locked:
		return
	if Net.arcade.handle_input(self, event):
		return
	detect_death(event)
	# reachable only while conscious thanks to the _unconscious guard above which is exactly right
	if event.is_action_pressed("revive"):
		_try_revive_nearby()
	var now := _time_since_start()
	detect_dodge(now, event)
	detect_death(event)

func detect_death(event: InputEvent) -> void:
	if event.is_action_pressed("death"):
		print("kys")
		_death()

func detect_dodge(now: float, event: InputEvent) -> void:
	Movement.detect_dodge(self, now, event)

func _dodge_left() -> void:
	Movement._dodge_left(self)

func _dodge_right() -> void:
	Movement._dodge_right(self)

func _dodge(local_dir: Vector3) -> void:
	Movement._dodge(self, local_dir)

func _jump(on_ground: bool) -> void:
	if Net.game_mode == Net.GameMode.ARCADE:
		Movement._jump_arcade(self, on_ground)
	else:
		Movement._jump(self, on_ground)


func _try_jump_cancel() -> bool:
	return Movement._try_jump_cancel(self)


func _can_cube_jump() -> bool:
	return Movement._can_cube_jump(self)

func _water_power_strength() -> float:
	return Combat._water_power_strength(self)

func _update_camera_pitch() -> void:
	Camera._update_camera_pitch(self)

func _death() -> void:
	Vitality._death(self)

@rpc("any_peer", "call_local", "reliable")
func net_death() -> void:
	Vitality.net_death(self)

func revive() -> void:
	Vitality.revive(self)

@rpc("any_peer", "call_local", "reliable")
func net_revive() -> void:
	Vitality.net_revive(self)


func respawn(at: Vector3, yaw: float) -> void:
	Vitality.respawn(self, at, yaw)

func _revive_target() -> Node:
	return Vitality._revive_target(self)


func _try_revive_nearby() -> void:
	Vitality._try_revive_nearby(self)


func _ensure_revive_prompt() -> Node:
	return Camera._ensure_revive_prompt(self)


func _update_revive_prompt() -> void:
	Camera._update_revive_prompt(self)


func _teammates_in_arena() -> Array:
	return Camera._teammates_in_arena(self)


func _update_nameplates() -> void:
	Camera._update_nameplates(self)


func _turn_from_input(delta: float) -> void:
	Movement._turn_from_input(self, delta)

func _drift_to_a_stop() -> void:
	Movement._drift_to_a_stop(self)


func _physics_process(delta: float) -> void:
	var _max_stamina = max_stamina_per_mode(Net.game_mode)
	# a remote body is a puppet its transform is replicated in from the peer
	if not _is_local():
		return
	_update_water_counter(delta)
	if Net.arcade.controls(self):
		return

	if _unconscious:
		# limp body input is ignored no turning no strokes no momentum but the water
		_drift_to_a_stop()
		return

	if Net.input_blocked_by_menu():
		_drift_to_a_stop()
		return

	if Net.is_spectating():
		_drift_to_a_stop()
		return

	if movement_locked:
		# same treatment as a limp body for a completely different reason the round hasnt
		_drift_to_a_stop()
		return

	_turn_from_input(delta)

	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_jump_cooldown_timer = maxf(_jump_cooldown_timer - delta, 0.0)
	_water_power_cooldown_timer = maxf(_water_power_cooldown_timer - delta, 0.0)
	_water_attack_cooldown_timer = maxf(_water_attack_cooldown_timer - delta, 0.0)
	_water_pelt_cooldown_timer = maxf(_water_pelt_cooldown_timer - delta, 0.0)

	# compute these once per tick in_shallow_end runs a raycast so dont call it or
	var submersion := _submersion()
	var shallow := in_shallow_end()
	Movement.update(self, delta, submersion, shallow)

	Combat.process_input(self, delta, submersion)

	# wire the numbers up to the bar see the exported stamina_ knobs above
	_stamina_change(delta)
	stamina = clampf(stamina, 0.0, _max_stamina)

func _submersion() -> float:
	return Movement._submersion(self)

func in_shallow_end() -> bool:
	return Movement.in_shallow_end(self)

func _swim_up_animation_time() -> float:
	return Movement._swim_up_animation_time(self)


func _swim_up_time_remaining() -> float:
	return Movement._swim_up_time_remaining(self)


func _apply_swim_up_anim_speed() -> void:
	Appearance._apply_swim_up_anim_speed(self)

func _water_height() -> float:
	return Movement._water_height(self)

func _mouse_aim_direction_3d(origin: Vector3) -> Vector3:
	return Camera._mouse_aim_direction_3d(self, origin)

func _mouse_aim_direction() -> Vector3:
	return Camera._mouse_aim_direction(self)

# gets time in seconds since started
func _time_since_start() -> float:
	return Time.get_ticks_msec() / 1000.0

func _walk(delta: float) -> void:
	Movement._walk(self, delta)

func _swim(delta: float) -> void:
	Movement._swim(self, delta)

func _glide(delta: float) -> void:
	Movement._glide(self, delta)

func _apply_water_drag(t: float) -> void:
	Movement._apply_water_drag(self, t)

func _apply_swim_motion(move_dir: Vector3, t: float) -> void:
	Movement._apply_swim_motion(self, move_dir, t)

func _wall_ahead(direction: Vector3) -> bool:
	return Movement._wall_ahead(self, direction)

func _stop_gliding() -> void:
	Movement._stop_gliding(self)

func _tread() -> void:
	Movement._tread(self)


func _apply_buoyancy(submersion: float) -> void:
	Movement._apply_buoyancy(self, submersion)

func _apply_central_force(force: Vector3) -> void:
	Movement._apply_central_force(self, force)
