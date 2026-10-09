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

enum Team {
	RED,
	BLUE,
}

# almost a copy of the movement state enum but with dodge left and right
enum AnimationState {
	IDLE,
	TREAD,
	SWIM_UP,
	SWIM,
	GLIDE,
	DODGE_LEFT,
	DODGE_RIGHT,
	WALK,
	JUMP,
}

# define this at the top of your script
const ANIM_MAP: Dictionary = {
	AnimationState.IDLE: "idle",
	AnimationState.TREAD: "tread",
	AnimationState.SWIM_UP: "swim_up",
	AnimationState.SWIM: "swim",
	AnimationState.GLIDE: "glide",
	AnimationState.DODGE_LEFT: "dodge_left",
	AnimationState.DODGE_RIGHT: "dodge_right",
	AnimationState.WALK: "walk",
	AnimationState.JUMP: "jump"
}

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
const _TEAM_WHITE_CUTOFF := 0.8

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
@export var jump_speed: float = 8.0
# how sharply momentum stops paying off the launch scales with momentum max_momentum jump_momentum_exponent so
@export_range(0.1, 1.0, 0.01) var jump_momentum_exponent: float = 0.5
# seconds after a jump before another one can trigger
@export var jump_cooldown: float = 1.0

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
@export var balance_mult: float = 0.5
@export var stamina_expended_dodge: float = 20.0 # cant dodge in the deep end
@export var stamina_in_shallow_end_per_second: float = 9.0 * balance_mult
@export var stamina_expended_in_deep_end_per_second_tread: float = 2.5 * balance_mult
@export var stamina_expended_in_deep_end_per_second_swim: float = 5.0 * balance_mult
@export var stamina_expended_in_deep_end_per_second_glide: float = 0.1 * balance_mult
@export var stamina_recovery_out_of_water_per_second: float = 9.0 * balance_mult
@export var water_power_stamina_cost: float = 10.0 * balance_mult
@export var water_attack_stamina_cost: float = 5.0 * balance_mult
@export var water_wall_stamina_cost_per_second: float = 20.0 * balance_mult

# seconds after casting before that same move can fire again same reasoning as dodge_cooldown
@export var water_power_cooldown: float = 0.6
@export var water_attack_cooldown: float = 0.4

# how much extra water_power strength banked momentum buys on top of the baseline 1
@export var water_power_momentum_bonus: float = 1.5
# diminishing returns on the momentum bonus same idiom and same reasoning as jump_momentum_exponent above
@export_range(0.1, 1.0, 0.01) var water_power_momentum_exponent: float = 0.6

@export_group("Teams")
# which side this body plays for drives the bodys colour see _apply_team_colors every white
@export var team: Team = Team.RED:
	set(value):
		team = value
		# same deferred until in tree reasoning as is_lifeguard below the mesh this recolours may
		if is_inside_tree():
			_apply_team_colors()

@export_group("Lifeguard")
# off duty by default on swaps blockbench_export for mesh lifeguard glb same rig animations
@export var is_lifeguard: bool = false:
	set(value):
		is_lifeguard = value
		# deferred to _ready at load time see there applied immediately here only for a
		if is_inside_tree():
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
# counts down after casting water_power water_attack until that same move can fire again see
var _water_power_cooldown_timer: float = 0.0
var _water_attack_cooldown_timer: float = 0.0
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
# the eyelid tween kept so revive can kill a close thats still in flight
var _eyelid_tween: Tween = null
# camera shake state see _shake_change
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_strength: float = 0.0

# the nodes name is the peer id that owns this body net gd names
func _enter_tree() -> void:
	_owner_peer = str(name).to_int()
	# 0 means the name isnt a peer id at all the scene opened on
	if _owner_peer > 0:
		set_multiplayer_authority(_owner_peer)
	else:
		# a body outside the real networked spawn system entirely e g menu tscns menuplayer
		var sync := get_node_or_null("MultiplayerSynchronizer")
		if sync:
			sync.queue_free()
	# lets net gd find the local player without assuming where in the tree it
	add_to_group("player")

# a raised water wall belongs to the ocean node not to this one so
func _exit_tree() -> void:
	if _ocean and _ocean.has_method("stop_water_wall"):
		_ocean.stop_water_wall(self)

# true when this body is the one this game window drives reads input owns
func _is_local() -> bool:
	return is_multiplayer_authority()

func _ready() -> void:
	mass = body_mass
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

	# everything past here belongs to whoever is playing in this window the one cursor
	if not _is_local():
		_setup_remote_body()
		return

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

	# tell anyone who joins later where we actually are the synchronizer only gets a
	if _owner_peer > 0 and not multiplayer.peer_connected.is_connected(_on_peer_joined):
		multiplayer.peer_connected.connect(_on_peer_joined)

	# drive the bars ranges from the real stat maxima theyre authored in the scene
	if gui:
		var stamina_bar: Range = gui.get_node_or_null("stamina_bar")
		if stamina_bar:
			stamina_bar.max_value = max_stamina
		var momentum_bar: Range = gui.get_node_or_null("momentum_bar")
		if momentum_bar:
			momentum_bar.max_value = max_momentum

	_underwater_mat = ShaderMaterial.new()
	_underwater_mat.shader = load("res://water/underwater.gdshader")

	# detach the camera rig from the body so it can lag behind and drift
	_cam_pivot_height = camera_hover_height
	call_deferred("_detach_camera_rig")
	_update_camera_pitch()

# applies or reverts every lifeguard buff to match is_lifeguard the kickboard rig and the
func _apply_lifeguard_loadout() -> void:
	if is_lifeguard:
		water_power_damage_max = _LIFEGUARD_WATER_POWER_DAMAGE_MAX
		water_attack_damage_max = _LIFEGUARD_WATER_ATTACK_DAMAGE_MAX
		momentum_gain_mult = _LIFEGUARD_MOMENTUM_GAIN_MULT
		momentum_loss_mult = _LIFEGUARD_MOMENTUM_LOSS_MULT
		water_wall_block_reduction = _LIFEGUARD_WATER_WALL_BLOCK_REDUCTION
	else:
		water_power_damage_max = _NORMAL_WATER_POWER_DAMAGE_MAX
		water_attack_damage_max = _NORMAL_WATER_ATTACK_DAMAGE_MAX
		momentum_gain_mult = _NORMAL_MOMENTUM_GAIN_MULT
		momentum_loss_mult = _NORMAL_MOMENTUM_LOSS_MULT
		water_wall_block_reduction = _NORMAL_WATER_WALL_BLOCK_REDUCTION
	_apply_mesh_for_lifeguard()

# swaps blockbench_export for the lifeguard rig mesh lifeguard glb kickboard included or back to
func _apply_mesh_for_lifeguard() -> void:
	var old := get_node_or_null("blockbench_export")
	if not (old and old.has_node("kickboard") == is_lifeguard):
		if old:
			remove_child(old)
			old.free()
		var mesh: Node3D = (_LIFEGUARD_MESH if is_lifeguard else _CHARACTER_MESH).instantiate()
		mesh.name = "blockbench_export"
		# matches player tscns own baked transform for this node exactly both rigs were modeled
		mesh.transform = Transform3D(Basis().scaled(Vector3.ONE * 0.5), Vector3(0.0, -1.0725327, 0.0))
		add_child(mesh)
		_anim_player = get_node_or_null("blockbench_export/AnimationPlayer")
		# _movement_anim_state tracks whats playing on a specific animationplayer instance a fresh one from the
		_movement_anim_state = -1
	# unconditional not just on the swapped branch above a freshly swapped animationplayer needs it
	_fix_animation_loop_modes()
	# likewise unconditional a swapped in rig arrives with the untouched imported material on every
	_apply_team_colors()


# paints this body in its teams colours by rebuilding each surfaces albedo texture with
func _apply_team_colors() -> void:
	var rig := get_node_or_null("blockbench_export")
	if rig == null:
		return
	var color: Color = _TEAM_COLORS.get(team, _TEAM_COLORS[Team.RED])
	for mesh_inst in _mesh_instances_in(rig):
		if mesh_inst.mesh == null:
			continue
		for surface in mesh_inst.mesh.get_surface_count():
			# read the material off the mesh resource never the active one get_active_material would resolve
			var base := mesh_inst.mesh.surface_get_material(surface)
			if not (base is StandardMaterial3D) or base.albedo_texture == null:
				continue
			var tinted := _tinted_texture(base.albedo_texture, color)
			if tinted == null:
				continue
			var mat: StandardMaterial3D = base.duplicate()
			mat.albedo_texture = tinted
			mesh_inst.set_surface_override_material(surface, mat)


# every meshinstance3d at or under node the rigs nest their parts several levels deep
func _mesh_instances_in(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_mesh_instances_in(child))
	return found


# cache of recoloured atlases keyed by source texture team colour shared by every player
static var _tint_cache: Dictionary = {}

# a copy of source with every near white texel replaced by color returns null
static func _tinted_texture(source: Texture2D, color: Color) -> ImageTexture:
	var key := [source.get_rid(), color]
	if _tint_cache.has(key):
		return _tint_cache[key]

	var img := source.get_image()
	if img == null:
		return null
	img = img.duplicate()
	# the atlases import as compressed vram textures see the import files get_pixel set_pixel dont
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	img.convert(Image.FORMAT_RGBA8)

	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a > 0.0 and minf(minf(px.r, px.g), px.b) >= _TEAM_WHITE_CUTOFF:
				# keep the source alpha the materials are alpha mask so overwriting it here would
				img.set_pixel(x, y, Color(color.r, color.g, color.b, px.a))

	var tex := ImageTexture.create_from_image(img)
	_tint_cache[key] = tex
	return tex

# water_wall is authored to loop for as long as its held and on mesh
func _fix_animation_loop_modes() -> void:
	if not _anim_player:
		return
	var loop_names: Array[String] = ["water_wall"]
	if not is_lifeguard:
		loop_names += _CHARACTER_LOOP_ANIMS
	for anim_name in loop_names:
		if _anim_player.has_animation(anim_name):
			_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

# turns this body into a puppet of the peer that owns it its transform
func _setup_remote_body() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	if is_instance_valid(_cam_pivot):
		_cam_pivot.queue_free()

func anim_name_to_string(anim_name: AnimationState) -> String:
	# looks up the string by enum key falls back to empty string if missing
	return ANIM_MAP.get(anim_name, "")

# used to compare against _movement_anim_state see there instead of animationplayer current_animation directly which reads
func play_anim(anim_state: AnimationState) -> void:
	if not _anim_player:
		return
	if _movement_anim_state == anim_state:
		return
	_movement_anim_state = anim_state
	if anim_state == AnimationState.SWIM_UP:
		# start it from the top at a sane rate _apply_swim_up_anim_speed called every frame from
		_anim_player.speed_scale = 1.0
		_anim_player.play("swim_up")
		_apply_swim_up_anim_speed()
	else:
		# anything else runs at its authored rate speed_scale is a property of the whole
		_anim_player.speed_scale = 1.0
		_anim_player.play(anim_name_to_string(anim_state))

# fires a one shot animation for water_power water_attack authored to hold on its last
func _play_water_action_anim(anim_name: String) -> void:
	if not _anim_player or not _anim_player.has_animation(anim_name):
		return
	# speed_scale belongs to the whole animationplayer and the swim_up wind up drives it well
	_anim_player.speed_scale = 1.0
	_anim_player.play(anim_name)
	_action_anim_lock_movement_state = movement_state
	# this clip now owns the animationplayer instead of play_anim s own bookkeeping invalidate it
	_movement_anim_state = -1

# starts keeps the looping water_wall animation in control of the animationplayer for as long
func _play_water_wall_anim() -> void:
	if not _anim_player or not _anim_player.has_animation("water_wall"):
		return
	if _anim_player.current_animation != "water_wall":
		# same reset same reason as _play_water_action_anim a wind up interrupted by raising the wall
		_anim_player.speed_scale = 1.0
		_anim_player.play("water_wall")
	_wall_anim_active = true
	_movement_anim_state = -1 # same reasoning as _play_water_action_anim

# releases water_walls hold on the animationplayer so _anim_change picks the movement animation back up
func _stop_water_wall_anim() -> void:
	_wall_anim_active = false

func _detach_camera_rig() -> void:
	# deferred a frame by _ready so the body can be gone by the time
	if not is_inside_tree() or not is_instance_valid(_cam_pivot):
		return
	# the scene root not get_parent the player used to sit directly under main so
	var root := get_tree().current_scene
	if root:
		_cam_pivot.reparent(root, true)

func _process(delta: float) -> void:
	# animation runs for every body local or not movement_state is replicated see player tscns
	if ANIMATE_PLAYER:
		_anim_change()

	# the camera the cursor and the shake are per window so they only make
	if not _is_local():
		return

	if CONTROL_CAMERA:
		_camera_pivot_change(delta)

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_shake_change(delta)
	_update_revive_prompt()
	_update_nameplates()

# decaying camera shake driven off h_offset v_offset rather than the cameras rotation or position
func _shake_change(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	if _shake_left <= 0.0 or _shake_total <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	var falloff := _shake_left / _shake_total
	_camera.h_offset = randf_range(-1.0, 1.0) * _shake_strength * falloff
	_camera.v_offset = randf_range(-1.0, 1.0) * _shake_strength * falloff

# kick off a camera shake strength in camera offset units small 0 05 is
func shake_camera(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_total = maxf(duration, 0.001)
	_shake_left = _shake_total

func _anim_change() -> void:
	if movement_state == MovementState.DODGE:
		return # todo handle in dodge functions
	if not _anim_player:
		return

	# out cold the death animation holds on its last frame and nothing should take
	if _unconscious:
		return

	# water_wall looping and water_power water_attack hold on last frame are playing themselves directly see
	if _wall_anim_active:
		return
	if _action_anim_lock_movement_state == movement_state:
		return
	_action_anim_lock_movement_state = -1

	match movement_state:
		MovementState.IDLE:
			play_anim(AnimationState.IDLE)
		MovementState.TREAD:
			play_anim(AnimationState.TREAD)
		MovementState.SWIM_UP:
			play_anim(AnimationState.SWIM_UP)
			# every frame not just on the state change the wind up its being fitted
			_apply_swim_up_anim_speed()
		MovementState.SWIM:
			play_anim(AnimationState.SWIM)
		MovementState.GLIDE:
			play_anim(AnimationState.GLIDE)
		MovementState.WALK:
			play_anim(AnimationState.WALK)
		MovementState.JUMP:
			play_anim(AnimationState.JUMP)


# water moves over the network which move net_cast_water_move is carrying sent as an int
enum WaterMove { POWER, ATTACK }

# fires a one shot water move on every peer only the local player ever
func _cast_water_move(kind: WaterMove, origin: Vector3, aim: Vector3, strength: float) -> void:
	if Net.is_online():
		# call_local so this covers us too no separate local call
		rpc("net_cast_water_move", kind, origin, aim, strength)
	else:
		net_cast_water_move(kind, origin, aim, strength)

@rpc("any_peer", "call_local", "reliable")
func net_cast_water_move(kind: WaterMove, origin: Vector3, aim: Vector3, strength: float) -> void:
	if _ocean == null:
		return
	# everyone draws the wave only the peer that cast it resolves what it hit
	var apply_hits := _is_local()
	# the damage range comes from this nodes own stats a lifeguards buffed water_power_damage_max water_attack_damage_max
	match kind:
		WaterMove.POWER:
			if _ocean.has_method("send_wave"):
				_ocean.send_wave(origin, aim, strength, self, apply_hits,
						water_power_damage_min, water_power_damage_max)
			_play_water_action_anim("water_power")
		WaterMove.ATTACK:
			if _ocean.has_method("send_attack_wave"):
				_ocean.send_attack_wave(origin, aim, strength, self, apply_hits,
						water_attack_damage_min, water_attack_damage_max)
			_play_water_action_anim("water_attack")

# the wall is held rather than fired so it re sends every frame its
func _cast_water_wall(origin: Vector3, aim: Vector3, strength: float) -> void:
	if Net.is_online():
		rpc("net_water_wall", origin, aim, strength)
	else:
		net_water_wall(origin, aim, strength)

@rpc("any_peer", "call_local", "unreliable")
func net_water_wall(origin: Vector3, aim: Vector3, strength: float) -> void:
	if _ocean and _ocean.has_method("start_water_wall"):
		# self keys the wall to this player so two people holding walls at once
		_ocean.start_water_wall(origin, aim, strength, self)
	_play_water_wall_anim()

# dropping the wall is reliable unlike the per frame updates above theres no follow
func _cast_water_wall_stop() -> void:
	if Net.is_online():
		rpc("net_water_wall_stop")
	else:
		net_water_wall_stop()

@rpc("any_peer", "call_local", "reliable")
func net_water_wall_stop() -> void:
	if _ocean and _ocean.has_method("stop_water_wall"):
		_ocean.stop_water_wall(self)
	_stop_water_wall_anim()

# someone new turned up send them our current state directly so they dont have
func _on_peer_joined(id: int) -> void:
	if not _is_local():
		return
	rpc_id(id, "net_sync_state", position, rotation, movement_state, _unconscious)

# current state of a body pushed to a peer that just joined everything here
@rpc("any_peer", "reliable")
func net_sync_state(pos: Vector3, rot: Vector3, state: MovementState, out_cold: bool) -> void:
	# never let a late packet stomp the body were actually driving
	if _is_local():
		return
	position = pos
	rotation = rot
	movement_state = state
	if out_cold and not _unconscious:
		net_death()

# knockback applied where this bodys physics actually run called by ocean_fluid_bridges _knockback via _send_to_owner
@rpc("any_peer", "reliable")
func net_apply_impulse(impulse: Vector3) -> void:
	if _is_local():
		apply_central_impulse(impulse)


func _camera_pivot_change(delta: float) -> void:
	if not is_instance_valid(_cam_pivot) or not _cam_pivot.is_inside_tree():
		return

	var target_pos := global_position + Vector3.UP * _cam_pivot_height
	_cam_pivot.global_position = _cam_pivot.global_position.lerp(
		target_pos, 1.0 - exp(-camera_follow_speed * delta))
	var target_yaw := global_transform.basis.get_euler().y
	var target_pitch := deg_to_rad(default_camera_pitch_deg)
	var target_angles := Vector2(target_yaw, target_pitch)
	if Input.is_action_pressed("look_scoreboard"):
		target_angles = _camera_look_angles(_scoreboard_look_node(), target_angles)
	var current_yaw := _cam_pivot.global_transform.basis.get_euler().y
	var new_yaw := lerp_angle(current_yaw, target_angles.x, 1.0 - exp(-camera_turn_speed * delta))
	_cam_pivot.global_rotation.y = new_yaw
	_camera.rotation.x = lerp_angle(
		_camera.rotation.x, target_angles.y,
		1.0 - exp(-camera_pitch_speed * delta))

	_gui_change()


func _camera_look_angles(target: Node3D, fallback: Vector2) -> Vector2:
	if target == null:
		return fallback
	var look := target.global_position - _cam_pivot.global_position
	var flat := Vector3(look.x, 0.0, look.z)
	if flat.length_squared() <= 0.001:
		return fallback
	var flat_dir := flat.normalized()
	var yaw := atan2(-flat_dir.x, -flat_dir.z)
	var local_look := Basis(Vector3.UP, yaw).inverse() * look.normalized()
	var pitch := clampf(
		atan2(local_look.y, -local_look.z),
		deg_to_rad(-75.0),
		deg_to_rad(45.0))
	return Vector2(yaw, pitch)


func _scoreboard_look_node() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var scoreboard := scene.get_node_or_null("Scoreboard")
	if not (scoreboard is Node3D):
		return null
	var title := scoreboard.get_node_or_null("SCORE")
	if title is Node3D:
		return title
	return scoreboard

func _gui_change() -> void:
	if not gui:
		return
	gui.get_node("stamina_bar").value = stamina
	gui.get_node("momentum_bar").value = momentum

func _stamina_change(delta: float) -> void:
	# bone dry not even wading so theres no water to be tired from recover
	if _submersion() <= 0.0:
		stamina += delta * stamina_recovery_out_of_water_per_second
		return

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

	if stamina <= 5.0:
		_death()

# called by ocean_fluid_bridge gd _apply_hit_damage when a water_power or water_attack wave lands on this
@rpc("any_peer", "reliable")
func take_stamina_damage(amount: float) -> void:
	if _water_wall_up:
		amount *= water_wall_block_reduction
	stamina = clampf(stamina - amount, 0.0, max_stamina)
	if stamina <= 5.0:
		_death()

func _input(event: InputEvent) -> void:
	# keystrokes in this window drive this windows player and nobody elses without this one
	if not _is_local():
		return
	if Net.input_blocked_by_menu():
		return
	if _unconscious:
		return
	# nothing lands before the countdown finishes not moves not the revive key not the
	if movement_locked:
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
	if ANIMATE_PLAYER:
		_anim_player.play("dodge_left")
		_movement_anim_state = -1 # same reasoning as _play_water_action_anim
	_dodge(Vector3.LEFT)

func _dodge_right() -> void:
	if ANIMATE_PLAYER:
		_anim_player.play("dodge_right")
		_movement_anim_state = -1
	_dodge(Vector3.RIGHT)

# a quick sideways burst triggered by double tapping left right see _input its a
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

	# 1 momentum and direction clamped to momentum_needed_to_swim too not just dodge_momentum a dodge is
	dir = (transform.basis * local_dir).normalized()
	momentum = max(momentum, dodge_momentum, momentum_needed_to_swim)

	# 2 impulse
	var right := _camera.global_basis.x
	if local_dir == Vector3.LEFT:
		right = -right
	apply_central_impulse(right * dodge_impulse)

# a jump off solid ground triggered by the jump action only works standing in
func _jump(on_ground: bool) -> void:
	if not on_ground or momentum <= 0.0 or _jump_cooldown_timer > 0.0:
		return
	_jump_cooldown_timer = jump_cooldown
	# diminishing returns on momentum the exponent 1 flattens the curve so arriving at full
	var t := clampf(momentum / max_momentum, 0.0, 1.0)
	linear_velocity.y = jump_speed * pow(t, jump_momentum_exponent)
	momentum = 0.0
	movement_state = MovementState.JUMP

# the strength a water_power cast fires at right now 1 0 baseline a cast
func _water_power_strength() -> float:
	var t := clampf(momentum / max_momentum, 0.0, 1.0)
	return 1.0 + water_power_momentum_bonus * pow(t, water_power_momentum_exponent)

# sets the cameras rotation x straight to the baked overhead tilt with no smoothing
func _update_camera_pitch() -> void:
	_camera.rotation.x = deg_to_rad(default_camera_pitch_deg)

# blacking out stamina hit zero control is gone and the body goes limp it
func _death() -> void:
	if _unconscious:
		return
	if Net.is_online():
		# call_local so this covers us as well as everyone else
		rpc("net_death")
	else:
		net_death()

@rpc("any_peer", "call_local", "reliable")
func net_death() -> void:
	if _unconscious:
		return
	_unconscious = true
	movement_state = MovementState.IDLE
	momentum = 0.0
	# stop taking input at the source rather than only ignoring it downstream _input stops
	set_process_input(false)

	# that may have been the last one standing on this side told rather than
	Net.call_deferred("on_player_down")

	# a wall left standing when its owner blacks out would hang in the pool
	if _water_wall_up:
		_water_wall_up = false
		if _ocean and _ocean.has_method("stop_water_wall"):
			_ocean.stop_water_wall(self)
	# clear the walls animation hold too whether or not a wall was up it
	_stop_water_wall_anim()

	# dropping played on every peer not just the dying one watching somebody go under
	if _anim_player and _anim_player.has_animation("death"):
		_anim_player.play("death")
		_movement_anim_state = -1 # same reasoning as _play_water_action_anim

	# past here is what blacking out looks like from behind your own eyes the
	if not _is_local():
		return

	if _muffled_player:
		_muffled_player.play()

	if _eyelid and _eyelid.material:
		# 0 0 is a wide open eye 1 0 fully shut see eye_closing gdshader
		_eyelid.material.set_shader_parameter("progress", 0.0)
		# half the ear ringing clip so the lids finish falling while the ring is
		var _duration := blackout_time
		if _muffled_player and _muffled_player.stream:
			_duration = _muffled_player.stream.get_length() / 2
		_eyelid_tween = create_tween()
		# linear on purpose progress isnt one animation any more its the clock the shader
		_eyelid_tween.set_trans(Tween.TRANS_LINEAR)
		_eyelid_tween.tween_method(
			func(val: float) -> void:
				var curved := 1.0 - pow(1.0 - val, 5.0)
				_eyelid.material.set_shader_parameter("progress", curved),
			0.0,
			1.0,
			_duration)

# coming to the mirror of _death eyes snap back open with a jolt through
func revive() -> void:
	if not _unconscious:
		return
	if Net.is_online():
		# call_local so this covers us as well as everyone else
		rpc("net_revive")
	else:
		net_revive()

@rpc("any_peer", "call_local", "reliable")
func net_revive() -> void:
	if not _unconscious:
		return
	_unconscious = false
	set_process_input(true)
	stamina = max_stamina * revive_stamina_fraction
	momentum = 0.0
	movement_state = MovementState.TREAD
	# the death clip holds on its last frame and _anim_change refuses to touch the
	_movement_anim_state = -1
	# a double tap registered before blacking out shouldnt cash in as a dodge the
	last_a_press = -1000.0
	last_d_press = -1000.0

	# past here is what coming round looks like from behind your own eyes the
	if not _is_local():
		return

	if _muffled_player:
		_muffled_player.stop()

	shake_camera(revive_shake_strength, revive_shake_time)

	if _eyelid and _eyelid.material:
		# kill the close if its still running or the two tweens would drive progress
		if _eyelid_tween and _eyelid_tween.is_valid():
			_eyelid_tween.kill()
		# snap open from wherever the lids actually are not from a fixed value so
		var from: float = _eyelid.material.get_shader_parameter("progress")
		_eyelid_tween = create_tween()
		_eyelid_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_eyelid_tween.tween_method(
			func(val: float) -> void:
				_eyelid.material.set_shader_parameter("progress", val),
			from,
			0.0,
			eyelid_open_time)

# lifeguard revives the downed teammate this body could pick up right now or null
func _revive_target() -> Node:
	if not is_lifeguard or _unconscious:
		return null
	var best: Node = null
	var best_dist := revive_range
	for other in get_tree().get_nodes_in_group("player"):
		if other == self or not is_instance_valid(other):
			continue
		# duck typed matching how the rest of this file talks to other bodies anything
		if not ("_unconscious" in other and "team" in other):
			continue
		if not other._unconscious or other.team != team:
			continue
		var dist := global_position.distance_to(other.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = other
	return best


# picks up whoever _revive_target nominated split from the input handler so the rules live
func _try_revive_nearby() -> void:
	var target := _revive_target()
	if target:
		target.revive()


# builds the floating r revive tag for this window once the first time its
func _ensure_revive_prompt() -> Node:
	if is_instance_valid(_revive_prompt):
		return _revive_prompt
	if gui == null:
		return null
	_revive_prompt = _REVIVE_PROMPT.instantiate()
	gui.add_child(_revive_prompt)
	return _revive_prompt


# keeps the prompt pointed at whoever we could pick up right now called every
func _update_revive_prompt() -> void:
	var target := _revive_target()
	# dont build the prompt just to be told theres nobody to revive a normal
	if target == null and not is_instance_valid(_revive_prompt):
		return
	var prompt := _ensure_revive_prompt()
	if prompt:
		prompt.show_for(target, _camera)


# every other body on this side right now never yourself theres no use floating
func _teammates_in_arena() -> Array:
	var mates: Array = []
	for other in get_tree().get_nodes_in_group("player"):
		if other == self or not is_instance_valid(other):
			continue
		# duck typed same as _revive_target above anything in the player group that has a
		if not ("team" in other) or other.team != team:
			continue
		mates.append(other)
	return mates


# keeps one floating nameplate per teammate for the local player only see _process built
func _update_nameplates() -> void:
	var wanted := {}
	for other in _teammates_in_arena():
		# the nodes name is the peer id same convention _enter_tree reads on the way
		var pid := str(other.name).to_int()
		if pid > 0:
			wanted[pid] = other

	# drop plates for anyone who no longer qualifies left the arena or never actually
	for pid in _nameplates.keys():
		if not wanted.has(pid):
			if is_instance_valid(_nameplates[pid]):
				_nameplates[pid].queue_free()
			_nameplates.erase(pid)

	if gui == null:
		return
	for pid in wanted:
		if not is_instance_valid(_nameplates.get(pid)):
			var plate := _NAMEPLATE.instantiate()
			gui.add_child(plate)
			_nameplates[pid] = plate
		_nameplates[pid].setup(wanted[pid], _camera, Net.name_of(pid))


# turns the body and the camera which follows its yaw see _process while a
func _turn_from_input(delta: float) -> void:
	var turn := Input.get_axis("left", "right")
	if turn == 0.0:
		_turn_hold_time = 0.0
		return

	var rate := turn_speed
	if exponential_turn_sensitivity:
		# same exponential approach idiom as camera_turn_speed camera_pitch_speed above 1 0 exp t tau ramps
		_turn_hold_time += delta
		rate *= 1.0 - exp(-_turn_hold_time / turn_ramp_time)
	else:
		_turn_hold_time = 0.0

	rotate_y(-turn * rate * delta)

# bleeds off whatever drift is left so the body coasts to a stop instead
func _drift_to_a_stop() -> void:
	var v := linear_velocity
	apply_central_force(
		Vector3(-v.x, 0.0, -v.z) * (water_linear_drag * 1.5) * mass)
	_apply_buoyancy(_submersion())


func _physics_process(delta: float) -> void:
	# a remote body is a puppet its transform is replicated in from the peer
	if not _is_local():
		return

	if _unconscious:
		# limp body input is ignored no turning no strokes no momentum but the water
		_drift_to_a_stop()
		return

	if Net.input_blocked_by_menu():
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

	# compute these once per tick in_shallow_end runs a raycast so dont call it or
	var submersion := _submersion()
	var shallow := in_shallow_end()

	if Input.is_action_just_pressed("jump"):
		# solid ground to push off the shallow ends floor or bone dry on the
		_jump(shallow or submersion <= 0.0)

	# entry exit splashes are handled by the water sim itself it detects the body

	# movement mode you can swim wherever theres enough water by holding the swim key
	var wants_swim := Input.is_action_pressed("swim_key")

	if wants_swim and (shallow or submersion > 0.25):
		_swim(delta)
	elif shallow:
		_walk(delta) # shallow end always walks unless actively swimming
	elif submersion > 0.25:
		_swim(delta) # not holding swim in open water glides
	else:
		_walk(delta)

	# gravity stays on everywhere buoyancy grows smoothly with submersion so the body has one
	if not (shallow and not wants_swim):
		_apply_buoyancy(submersion)

	# baseline momentum for wading in the shallows
	if shallow:
		momentum = max(momentum_in_shallow_end, momentum)

	# water power press 1 send a wave skimming across the surface toward wherever the
	if submersion > 0.0 and Input.is_action_just_pressed("water_power") \
			and stamina >= water_power_stamina_cost \
			and _water_power_cooldown_timer <= 0.0 \
			and _ocean and _ocean.has_method("send_wave"):
		var aim := _mouse_aim_direction()
		var origin := global_position + aim * 1.0
		origin.y = _water_height()
		# the wave and its animation are raised on every peer from inside the rpc
		_cast_water_move(WaterMove.POWER, origin, aim, _water_power_strength())
		stamina -= water_power_stamina_cost
		_water_power_cooldown_timer = water_power_cooldown
		# spent not banked _water_power_strength already read momentum to compute the strength argument above evaluated
		momentum = 0.0

	# water attack water_attack action close range counterpart to water power a much bigger denser
	if submersion > 0.0 and Input.is_action_just_pressed("water_attack") \
			and stamina >= water_attack_stamina_cost \
			and _water_attack_cooldown_timer <= 0.0 \
			and _ocean and _ocean.has_method("send_attack_wave"):
		var attack_aim := _mouse_aim_direction()
		var attack_origin := global_position + attack_aim * 0.6
		attack_origin.y = _water_height()
		_cast_water_move(WaterMove.ATTACK, attack_origin, attack_aim, 1.0)
		stamina -= water_attack_stamina_cost
		_water_attack_cooldown_timer = water_attack_cooldown

	# water wall water_wall action hold 3 raises a stationary wall of water in front
	if submersion > 0.0 and Input.is_action_pressed("water_wall") and stamina > 0.0 \
			and _ocean and _ocean.has_method("start_water_wall"):
		var wall_aim := _mouse_aim_direction()
		var wall_origin := global_position + wall_aim * 1.2
		wall_origin.y = _water_height()
		_cast_water_wall(wall_origin, wall_aim, 1.0)
		_water_wall_up = true
		stamina -= water_wall_stamina_cost_per_second * delta
	elif _water_wall_up:
		# only on the frame it actually drops not every frame the key is idle
		_cast_water_wall_stop()
		_water_wall_up = false

	# wire the numbers up to the bar see the exported stamina_ knobs above
	_stamina_change(delta)
	stamina = clampf(stamina, 0.0, max_stamina)

# fraction of the body below the water surface 0 fully out 1 fully under
func _submersion() -> float:
	var bottom := global_position.y - body_half_height
	return clampf((_water_height() - bottom) / (2.0 * body_half_height), 0.0, 1.0)

# true when the player is standing on the bottom while still partly in the
func in_shallow_end() -> bool:
	var water_y := _water_height()
	# not in the water at all nothing to be shallow in
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
	# which mesh is underfoot isnt enough on its own transition is one long ramp
	return water_y - result.position.y <= 2.0 * body_half_height

func _swim_up_animation_time() -> float:
	if momentum >= momentum_needed_to_swim:
		return 0.0

	var t = momentum / momentum_needed_to_swim
	return lerp(0.5, 1.5, t)


# seconds of wind up actually left before momentum reaches the swim threshold at the
func _swim_up_time_remaining() -> float:
	if momentum_needed_to_swim <= 0.0:
		return 0.0
	var k := _swim_gain_scale * momentum_gain_mult
	if k <= 0.0:
		return 0.0
	var u := clampf(momentum / momentum_needed_to_swim, 0.0, 1.0)
	return (1.0 - u * 0.5 - u * u * 0.5) / k


# paces the swim_up clip so it plays through exactly once over the wind up
func _apply_swim_up_anim_speed() -> void:
	if not _anim_player or not _anim_player.has_animation("swim_up"):
		return
	# reads once a loop_none clip has finished and is holding its last frame nothing
	if _anim_player.current_animation != "swim_up":
		return
	var anim := _anim_player.get_animation("swim_up")
	var clip_len := anim.length if anim else 0.0
	if clip_len <= 0.0:
		clip_len = SWIM_UP_ANIMATION_BASE_TIME
	var clip_left := maxf(clip_len - _anim_player.current_animation_position, 0.0)
	var time_left := _swim_up_time_remaining()
	if clip_left <= 0.0 or time_left <= 0.0:
		_anim_player.speed_scale = 1.0
		return
	# clamped right at the threshold time_left goes to zero and an unclamped ratio would
	_anim_player.speed_scale = clampf(
		clip_left / time_left, _SWIM_UP_MIN_SPEED, _SWIM_UP_MAX_SPEED)

# world space height of the water surface used for submersion and so for buoyancy
func _water_height() -> float:
	if _ocean:
		if _ocean.has_method("get_rest_height"):
			return _ocean.get_rest_height()
		if _ocean.has_method("get_height_at"):
			return _ocean.get_height_at(global_position)
	return 0.0

# horizontal direction from the player toward wherever the mouse cursor is pointing for aiming
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

# gets time in seconds since started
func _time_since_start() -> float:
	return Time.get_ticks_msec() / 1000.0

func _walk(delta: float) -> void:
	can_move = true
	# forward back only left right now turn instead of strafing see _turn_from_input same as
	var input_dir := Vector2(0.0, Input.get_axis("forward", "back"))
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# walk while moving idle when standing still
	movement_state = MovementState.WALK if direction else MovementState.IDLE

	# momentum is the only speed modifier so walking wading builds momentum too but only
	if direction:
		momentum = move_toward(momentum, max_momentum_by_walking, SWIM_GAIN * delta)
	else:
		momentum = move_toward(momentum, 0.0, SWIM_GAIN * delta)

	# speed comes from momentum via the shared drag thrust so wading has the same
	_apply_swim_motion(direction, momentum / max_momentum)

func _swim(delta: float) -> void:
	var in_shallow := in_shallow_end()
	if DEBUG_IN_SHALLOW_WATER:
		print("in_shallow: ", in_shallow)
	if not Input.is_action_pressed("swim_key"):
		_glide(delta)
		return
	# actively swimming re enables movement after a tread stopped it so the player isnt
	can_move = true
	# momentum 0 0 1 0
	var t := momentum / max_momentum

	# intentional swim thrust direction horizontal only forward back only left right turn instead of
	var input_dir := Vector2(0.0, Input.get_axis("forward", "back"))
	if Input.is_action_pressed("back"):
		_last_backstroke_time = _time_since_start()
	# switch a backstroke s straight into a forward stroke w without releasing the swim
	if (Input.is_action_just_pressed("forward")
			and _time_since_start() - _last_backstroke_time <= BACKSTROKE_FLIP_WINDOW):
		rotate_y(PI)

	# horizontal only off the bodys own facing same as _walk not the cameras the
	dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y))

	# with enough momentum already banked a stroke should just move instantly not ease in
	if momentum >= momentum_needed_to_swim and dir.length() > 0.01:
		var speed := Vector2(linear_velocity.x, linear_velocity.z).length()
		var redirected := dir.normalized() * speed
		linear_velocity.x = redirected.x
		linear_velocity.z = redirected.z

	# the wake ripples and bow wave come purely from the fluid sim reacting to

	# build momentum only while actually pushing forward back holding swim_key alone with no w
	if input_dir.y != 0.0:
		# during the swim up wind up pace it so momentum reaches the swim threshold
		var gain_scale := forward_swim_gain_mult if input_dir.y < 0.0 else 1.0
		# cached for _swim_up_time_remaining so the wind up animation is paced off the same stroke
		_swim_gain_scale = gain_scale
		var swim_up_time := _swim_up_animation_time()
		if swim_up_time > 0.0:
			momentum += momentum_needed_to_swim / swim_up_time * delta * gain_scale * momentum_gain_mult
		else:
			momentum += SWIM_GAIN * pow(1.0 - t, 2.0) * delta * gain_scale * momentum_gain_mult
		momentum = min(momentum, max_momentum)
	else:
		# deep water idle decay momentum_loss_mult is the kickboards lose less in the deep end
		momentum = move_toward(momentum, 0.0, SWIM_GAIN * delta * momentum_loss_mult)

	# swim_up is the wind up phase spent building the momentum needed to swim see
	movement_state = MovementState.SWIM if momentum >= momentum_needed_to_swim else MovementState.SWIM_UP

	# drag thrust shared with gliding so both top out at the same speed
	_apply_swim_motion(dir, t)

func _glide(delta: float) -> void:
	# go along path conserving momentum but not gaining any basically like swimming but lose
	var glide_dir := Vector3(dir.x, 0.0, dir.z)

	# press a movement key to cancel the glide or stop dead if we hit
	if (Input.is_action_just_pressed("forward")
			or Input.is_action_just_pressed("back")
			or _wall_ahead(glide_dir)):
		_stop_gliding()
		return

	if momentum > 0.0:
		movement_state = MovementState.GLIDE
		# momentum_loss_mult the other deep water spot the kickboards lose less applies alongside _swim s
		momentum -= SWIM_GAIN * delta * momentum_loss_mult
		var t = momentum / max_momentum
		_apply_swim_motion(glide_dir, t)
	else:
		momentum = 0.0
		_tread()

# water drag opposing whatever the bodys current velocity actually is for momentum fraction t
func _apply_water_drag(t: float) -> void:
	var v := linear_velocity
	var drag: float = lerp(water_linear_drag * 1.5, water_linear_drag * 0.5, t)
	_apply_central_force(Vector3(-v.x, 0.0, -v.z) * drag * mass)

# water drag plus forward thrust for the given momentum fraction t and move direction
func _apply_swim_motion(move_dir: Vector3, t: float) -> void:
	_apply_water_drag(t)
	if move_dir.length() > 0.01:
		var swim_force: float = lerp(swim_speed * 0.5, swim_speed * 1.5, t)
		_apply_central_force(move_dir.normalized() * swim_force * mass)

# true when a genuinely vertical surface is within wall_probe ahead along direction a wall
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

# halt a glide kill horizontal speed and drop back to treading
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


# archimedes buoyancy upward acceleration is proportional to how much of the body is submerged
func _apply_buoyancy(submersion: float) -> void:
	var v := linear_velocity
	# lift submersion target g at the target depth this equals gravity which the engine
	var lift_accel := submersion / target_submersion * _gravity
	# auto critical damping the springs stiffness is k g 2h target so a damping
	var k := _gravity / (2.0 * body_half_height * target_submersion)
	var damping := 2.0 * damping_ratio * sqrt(k)
	# damping scales with submersion alongside the lift so out of the water this whole
	var accel := lift_accel - v.y * damping * submersion
	# buoyancy is passive physics apply it directly never gated by can_move or the player
	apply_central_force(Vector3.UP * accel * mass)

func _apply_central_force(force: Vector3) -> void:
	if can_move:
		apply_central_force(force)
