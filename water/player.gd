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

# Almost a copy of the movement state enum, but with dodge left and right.
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

# Define this at the top of your script
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
## Fallback clip length for swim_up, only used if the real length can't be
## read off the AnimationPlayer. The actual length is measured from the clip
## itself (see _apply_swim_up_anim_speed) so re-exporting the rig at a
## different length can't silently put the wind-up out of time.
const SWIM_UP_ANIMATION_BASE_TIME := 0.5
## Bounds on the swim_up playback rate. Without a ceiling the last frames blur
## as the remaining wind-up time goes to zero; without a floor a very slow
## build-up would leave the clip looking frozen.
const _SWIM_UP_MIN_SPEED := 0.25
const _SWIM_UP_MAX_SPEED := 4.0
const DODGE_DOUBLE_TAP_TIME := 0.25
const CONTROL_CAMERA := true
const ANIMATE_PLAYER := true
const DEBUG_IN_SHALLOW_WATER: bool = false

# Normal vs. lifeguard numbers for is_lifeguard's stat buffs (see
# _apply_lifeguard_loadout() below). Both sides are named consts, not just the
# lifeguard side, so a normal-player number never has to be duplicated between
# an export default and the "turn it back off" branch.
const _NORMAL_WATER_POWER_DAMAGE_MAX := 30.0
const _NORMAL_WATER_ATTACK_DAMAGE_MAX := 65.0
const _NORMAL_MOMENTUM_GAIN_MULT := 1.0
const _NORMAL_MOMENTUM_LOSS_MULT := 1.0
const _NORMAL_WATER_WALL_BLOCK_REDUCTION := 0.5 # halves an incoming hit while blocking

const _LIFEGUARD_WATER_POWER_DAMAGE_MAX := 60.0
const _LIFEGUARD_WATER_ATTACK_DAMAGE_MAX := 80.0
const _LIFEGUARD_MOMENTUM_GAIN_MULT := 1.3
const _LIFEGUARD_MOMENTUM_LOSS_MULT := 0.5
const _LIFEGUARD_WATER_WALL_BLOCK_REDUCTION := 0.1 # the kickboard block: 90% of the hit never lands

const _CHARACTER_MESH := preload("res://mesh/character.glb")
const _LIFEGUARD_MESH := preload("res://mesh/lifeguard.glb")
const _REVIVE_PROMPT := preload("res://water/revive_prompt.tscn")

# Team kit colours. Both rigs (mesh/character.glb, mesh/lifeguard.glb) are
# textured off a 16x16 Blockbench atlas whose only pure-white texels are the
# trunks/trim -- 68 of them on each -- so recolouring exactly white is what
# turns a body into a team kit without touching skin, hair or the kickboard.
# See _apply_team_colors().
const _TEAM_COLORS: Dictionary = {
	Team.RED: Color("d92d2d"),
	Team.BLUE: Color("2d6bd9"),
}
# How close to white a texel has to be to count as kit. The atlases only ever
# use pure white (255,255,255) for it, and the next-brightest colour on either
# rig is the lifeguard's red at (223,45,45) -- whose min channel is 0.18 --
# so anything above ~0.8 on every channel separates them with room to spare.
const _TEAM_WHITE_CUTOFF := 0.8

## Movement-state clip names (see ANIM_MAP) that should genuinely loop
## (LOOP_LINEAR) on mesh/character.glb's rig -- they're authored as
## continuous cycles (a walk cycle, a treading-water loop, etc.). glTF import
## always bakes every clip in at LOOP_NONE regardless of what Blockbench's own
## loop setting was (glTF has no concept of animation looping, so that
## authoring-time setting can never survive export) -- these need it set
## explicitly, same as water_wall already did. mesh/lifeguard.glb's
## equivalents are authored as single held poses instead, per its own
## Blockbench project, so they're deliberately left off this list -- see
## _fix_animation_loop_modes().
## swim_up is deliberately NOT in this list, unlike every other movement clip.
## It isn't a cycle -- it's a one-shot wind-up that plays through exactly once
## while momentum builds toward the swim threshold, stretched to fit however
## long that actually takes (see _apply_swim_up_anim_speed). Looping it meant
## the wind-up restarted over and over for the whole build-up instead of
## reading as one continuous effort.
const _CHARACTER_LOOP_ANIMS: Array[String] = ["idle", "tread", "swim", "glide", "walk", "jump"]

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
## mouse look still adjusts freely from there within the usual clamp. More
## negative = looking down more steeply, i.e. a higher-feeling angle.
## "Angle" in the Settings menu -- see settings.gd's camera_pitch_deg.
@export var default_camera_pitch_deg: float = -36.0
## How high above the player CamPivot hovers, in metres -- baked into
## water/player.tscn's CamPivot transform by default, but overridable here so
## Settings.apply_to() (see settings.gd) can push a saved value onto the
## local player at _ready(). "Camera arc" in the Settings menu.
@export var camera_hover_height: float = 3.2
## How quickly the camera rig's position catches up to the player, in 1/seconds
## (exponential smoothing, frame-rate independent). Lower = more of a drone lag
## drifting into place; higher = tracks tighter. Not instant like a rigidly
## parented camera would be.
@export var camera_follow_speed: float = 5.0
## Same idea but for which way the rig is facing (yaw).
@export var camera_turn_speed: float = 4.0
## Same idea but for mouse-look pitch settling into place, instead of snapping.
@export var camera_pitch_speed: float = 8.0

## Whether A/D turning ramps up the longer the key is held, instead of
## applying turn_speed instantly -- "exponential sensitivity" in Settings.
## See _turn_from_input().
@export var exponential_turn_sensitivity: bool = false
## Seconds of continuous A/D hold to reach ~95% of full turn_speed when
## exponential_turn_sensitivity is on. Only matters while that's enabled.
@export var turn_ramp_time: float = 0.6

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
## Off for a purely decorative player -- one dropped into a scene (e.g. the
## menu background, see menu/menu.gd) to be walked around for show while some
## other, fixed camera actually owns the view. Leaves this player's own camera
## rig in the scene but never makes it .current, and skips the mouse-capture
## dance in _ready(). On (the default) is every normal gameplay case, local
## or networked -- unchanged from before this existed.
@export var take_over_camera: bool = true
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
## Launch speed in m/s at full momentum, straight up. Actual height is
## roughly jump_speed^2 / (2 * gravity), so 8.0 tops out around 3.2 m.
@export var jump_speed: float = 8.0
## How sharply momentum stops paying off. The launch scales with
## (momentum / max_momentum) ^ jump_momentum_exponent, so below 1.0 each extra
## point of momentum buys less than the last:
##   1.0  -> linear, double the momentum is double the launch
##   0.5  -> double the momentum is 1.41x the launch
##   0.33 -> double the momentum is 1.26x the launch
## Momentum is still worth building, it just can't run away with the jump.
@export_range(0.1, 1.0, 0.01) var jump_momentum_exponent: float = 0.5
## Seconds after a jump before another one can trigger.
@export var jump_cooldown: float = 1.0

@export_group("Blackout")
## Fallback for how long the eyelids take to fall shut. Normally the close is
## timed off the ear-ringing clip instead (half its length, see _death); this
## only applies when that stream is missing.
@export var blackout_time: float = 4.5
## Seconds the eyelids take to fly back open on revive(). Much shorter than the
## close -- coming round is a jolt, blacking out is a slide.
@export var eyelid_open_time: float = 0.22
## How much of the tank revive() hands back, as a fraction of max_stamina. Must
## stay above 0 or the player blacks out again on the next tick; low values give
## you a groggy few seconds before you have to reach the shallows.
@export_range(0.05, 1.0, 0.01) var revive_stamina_fraction: float = 0.5
## Camera jolt on revive, in camera-offset units. Tiny by design -- 0.06 reads
## as a flinch; past ~0.3 it's a car crash.
@export var revive_shake_strength: float = 0.06
## Seconds that jolt takes to decay to nothing.
@export var revive_shake_time: float = 0.25
## How close a lifeguard has to be to pick a downed teammate up, in metres.
## Generous enough that you don't have to fight the water to line the two
## bodies up, tight enough that it still reads as "standing over them" -- the
## player capsule is ~2m tall for scale. Also the range the on-screen prompt
## appears at, since both read _revive_target().
@export var revive_range: float = 3.0

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
@export var balance_mult: float = 0.5
@export var stamina_expended_dodge: float = 20.0 # can't dodge in the deep end
@export var stamina_in_shallow_end_per_second: float = 9.0 * balance_mult
@export var stamina_expended_in_deep_end_per_second_tread: float = 2.5 * balance_mult
@export var stamina_expended_in_deep_end_per_second_swim: float = 5.0 * balance_mult
@export var stamina_expended_in_deep_end_per_second_glide: float = 0.1 * balance_mult
@export var stamina_recovery_out_of_water_per_second: float = 9.0 * balance_mult
@export var water_power_stamina_cost: float = 10.0 * balance_mult
@export var water_attack_stamina_cost: float = 5.0 * balance_mult
@export var water_wall_stamina_cost_per_second: float = 20.0 * balance_mult

## Seconds after casting before that same move can fire again -- same
## reasoning as dodge_cooldown/jump_cooldown above: no throwing another one
## before your arms have recovered from the last. water_wall has no cooldown
## of its own on purpose -- it's a hold, not a cast, so nothing to spam; its
## stamina drain already limits how long it can stay up.
@export var water_power_cooldown: float = 0.6
@export var water_attack_cooldown: float = 0.4

## How much extra water_power strength banked momentum buys, on top of the
## baseline 1.0 you get standing still -- full momentum makes a cast this many
## times stronger overall (see _water_power_strength()). "Overall" because
## strength isn't just a damage multiplier in ocean_fluid_bridge.gd's
## send_wave() -- reach, width and knockback all scale with it too, so a
## momentum-boosted cast genuinely reaches further and hits harder, the same
## way charging in with speed would in real water.
##
## Only water_power (key 1) reads momentum this way -- water_attack is the
## close-range, stand-your-ground option, so tying it to how fast you're
## already moving wouldn't fit it the same way.
@export var water_power_momentum_bonus: float = 1.5
## Diminishing returns on the momentum bonus, same idiom (and same reasoning)
## as jump_momentum_exponent above: below 1.0, the early momentum you build
## pays off faster than the last bit, rather than the bonus scaling linearly
## all the way to max_momentum.
@export_range(0.1, 1.0, 0.01) var water_power_momentum_exponent: float = 0.6

@export_group("Teams")
## Which side this body plays for. Drives the body's colour (see
## _apply_team_colors(): every white texel on the rig becomes this team's
## colour) and who a lifeguard is allowed to revive (see _revive_target()).
##
## Deliberately NOT a friendly-fire gate -- teammates can absolutely hit each
## other. take_stamina_damage() doesn't look at teams at all, on purpose.
##
## The host picks this per player at spawn (see net.gd's _add_player) and it
## replicates in the spawn packet, so every peer agrees on every body's team
## from the moment it appears. Hand-placed bodies outside the networked
## roster -- menu.tscn's MenuPlayer -- just keep whatever's set here.
@export var team: Team = Team.RED:
	set(value):
		team = value
		# Same deferred-until-in-tree reasoning as is_lifeguard below: the
		# mesh this recolours may not exist yet while the scene file is still
		# being deserialized into this node.
		if is_inside_tree():
			_apply_team_colors()

@export_group("Lifeguard")
## Off-duty by default. On: swaps blockbench_export for mesh/lifeguard.glb
## (same rig/animations as mesh/character.glb, kickboard included -- see
## _apply_mesh_for_lifeguard()) and buffs several stats below to match --
## bigger max hit damage, faster momentum gain, less momentum lost in the
## deep end, and a much better water_wall block. Safe to flip either
## direction, live or baked into the scene file: see the setter.
@export var is_lifeguard: bool = false:
	set(value):
		is_lifeguard = value
		# Deferred to _ready() at load time (see there) -- applied immediately
		# here only for a genuine LIVE toggle, i.e. this node is already fully
		# built and in the tree, not still being deserialized. Swapping
		# blockbench_export while this node's OWN children (blockbench_export
		# included) might not exist yet would leave a duplicate mesh behind
		# instead of replacing the one the scene file is about to add.
		if is_inside_tree():
			_apply_lifeguard_loadout()

## Damage range at strength 1 for a hit that lands -- see
## ocean_fluid_bridge.gd's _apply_hit_damage(), which picks a point along
## this range based on where along the wave's path the hit landed. Only the
## *_max ends change for a lifeguard (per spec); the mins are the same for
## everyone.
@export var water_power_damage_min: float = 8.0
@export var water_power_damage_max: float = _NORMAL_WATER_POWER_DAMAGE_MAX
@export var water_attack_damage_min: float = 35.0
@export var water_attack_damage_max: float = _NORMAL_WATER_ATTACK_DAMAGE_MAX

## Multiplies momentum gained while swimming, and momentum lost per second
## while idling in open water or gliding -- see _swim()/_glide(). >1 gains
## faster; <1 loses less.
@export var momentum_gain_mult: float = _NORMAL_MOMENTUM_GAIN_MULT
@export var momentum_loss_mult: float = _NORMAL_MOMENTUM_LOSS_MULT

## Fraction of an incoming hit that still gets through while holding a water
## wall up -- see take_stamina_damage(). 0.5 is a 50% block, 0.1 is 90%.
@export var water_wall_block_reduction: float = _NORMAL_WATER_WALL_BLOCK_REDUCTION
@export_group("") # closes "Lifeguard" -- movement_state etc. below are ungrouped again

var dir: Vector3 = Vector3.ZERO
var can_move: bool = true
# get_node_or_null, not get_node: a decorative player dropped into a scene with
# no HUD (see menu/menu.gd) has nothing at this path at all, and get_node's hard
# error on a miss would take down the rest of _ready() with it -- the camera
# detach, the underwater material, everything after this point never runs.
# Every read of `gui` below is guarded the same way for the same reason.
@onready var gui: CanvasLayer = get_node_or_null("/root/Main/gui")
# Movement state: state of movement 👍
@export var movement_state: MovementState = MovementState.IDLE
var _ocean: Node = null
# Counts down after a dodge/jump until another one is allowed.
var _dodge_cooldown_timer: float = 0.0
var _jump_cooldown_timer: float = 0.0
# Counts down after casting water_power/water_attack until that same move can
# fire again -- see water_power_cooldown/water_attack_cooldown above.
var _water_power_cooldown_timer: float = 0.0
var _water_attack_cooldown_timer: float = 0.0
# How long A/D has been continuously held -- resets the instant it's released.
# Only read when exponential_turn_sensitivity is on; see _turn_from_input().
var _turn_hold_time: float = 0.0

# water_power/water_attack are authored to hold on their last frame; this
# tracks the movement_state they were fired during, so _anim_change() leaves
# them alone (instead of snapping straight back to the movement animation
# next frame) until movement actually changes to something else. -1 = no
# action animation in control. See _play_water_action_anim().
var _action_anim_lock_movement_state: int = -1
# Which AnimationState play_anim() last told the AnimationPlayer to play,
# tracked independently of what the player itself reports -- see play_anim()
# for why that matters. -1 = nothing played yet, or something else (a water
# move, a dodge, death) currently owns the AnimationPlayer instead and
# _anim_change() needs to unconditionally re-assert control the next time it
# resumes, whatever movement_state happens to already be.
var _movement_anim_state: int = -1
# water_wall loops for as long as the key is held; this just tells
# _anim_change() to leave the AnimationPlayer alone while that's true. See
# _play_water_wall_anim()/_stop_water_wall_anim().
var _wall_anim_active: bool = false
# True while the water wall is up -- take_stamina_damage() halves incoming
# damage while this is set. The defend half of "later it will defend" the
# wall's own doc comment mentioned.
var _water_wall_up: bool = false
# The peer this body belongs to, read off the node name in _enter_tree. 0 when
# the name isn't a peer id (the scene opened standalone).
var _owner_peer: int = 0
# This window's floating "[R] Revive" tag, built on demand -- see
# _ensure_revive_prompt().
var _revive_prompt: Node = null
## The stroke scaling _swim() last built momentum with (direction times the
## lifeguard buff). Cached so _swim_up_time_remaining() paces the wind-up
## animation off the same number the physics used. Defaults to 1.0, which is
## also what a remote body ends up using -- momentum isn't replicated, so
## somebody else's wind-up is paced at the nominal rate rather than exactly.
var _swim_gain_scale: float = 1.0
## Set while the round hasn't begun -- bodies are spawned on their team's side
## of the pool and held there through the countdown, then everyone is released
## at once (see net.gd's start_round/_run_countdown). Separate from
## _unconscious even though both mean "takes no input": this one carries none
## of the blackout's baggage (no death animation, no eyelids, no ear ringing),
## and a body that goes down mid-round must not come back as "locked".
var movement_locked: bool = false

@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _cam_pivot: Node3D = $CamPivot
# get_node_or_null -- see the comment on `gui` above; same failure mode.
@onready var _muffled_player: AudioStreamPlayer = get_node_or_null("/root/Main/muffled_player")
# The scene's named floor meshes; see in_shallow_end(). shallow and
# transition both count as walkable; deep never does.
@onready var _shallow_floor: Node = get_node_or_null("/root/Main/shallow")
@onready var _transition_floor: Node = get_node_or_null("/root/Main/transition")
@onready var _eyelid: ColorRect = get_node_or_null("/root/Main/gui/eyelid")
@onready var _anim_player: AnimationPlayer = get_node_or_null("blockbench_export/AnimationPlayer")
var _underwater_mat: ShaderMaterial

# Height above the body the camera rig hovers at, captured from the scene
# before we detach the rig from the body below.
var _cam_pivot_height: float = 0.0
var _gravity: float = 9.8
# Timestamp of the last physics tick we were backstroking (holding S while
# swim_key is held); see BACKSTROKE_FLIP_WINDOW.
var _last_backstroke_time: float = -1000.0
# Latched by _death() once stamina runs out; see there. Gates input and the
# whole movement pass, so nothing can swim the body around while it's out.
var _unconscious: bool = false
# The eyelid tween, kept so revive() can kill a close that's still in flight
# instead of letting the two fight over the same shader parameter.
var _eyelid_tween: Tween = null
# Camera shake state; see _shake_change.
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_strength: float = 0.0

## The node's name is the peer id that owns this body -- net.gd names it that
## when it spawns one, and the name replicates along with the node, so every
## peer independently agrees on who controls which player.
##
## _enter_tree rather than _ready on purpose: the MultiplayerSynchronizer child
## reads this body's authority when it starts up, and children are readied
## before their parent. Setting it in _ready would leave the synchronizer a
## frame behind, replicating from the wrong peer.
func _enter_tree() -> void:
	_owner_peer = str(name).to_int()
	# 0 means the name isn't a peer id at all (the scene opened on its own, or
	# somebody renamed the node). Leave the default authority alone rather than
	# setting an invalid one.
	if _owner_peer > 0:
		set_multiplayer_authority(_owner_peer)
	else:
		# A body outside the real networked spawn system entirely -- e.g.
		# menu.tscn's MenuPlayer, a purely decorative, always-local walk-around
		# instance with no business ever being networked. Its
		# MultiplayerSynchronizer would otherwise still try to broadcast this
		# body's transform to ANY peer that connects while it's still in the
		# tree (a host sitting on the menu, say) -- REGARDLESS of what scene
		# that peer is actually on, since MultiplayerSynchronizer doesn't know
		# or care that this is "just the menu background". That produced real,
		# connection-breaking RPC errors ("Node not found:
		# .../MenuPlayer/MultiplayerSynchronizer") the moment a client
		# connected while the host was still sitting on the menu -- removing
		# the synchronizer outright, rather than trying to scope its
		# visibility, is what actually guarantees this body can never
		# replicate to anyone, ever, regardless of what future multiplayer
		# features get added.
		var sync := get_node_or_null("MultiplayerSynchronizer")
		if sync:
			sync.queue_free()
	# Lets net.gd find "the local player" without assuming where in the tree
	# it lives -- under a real gameplay scene's "Players" spawner, or a
	# hand-placed instance like menu.tscn's MenuPlayer, which sits outside
	# that whole system. See net.gd's test_lifeguard_key handling.
	add_to_group("player")

## A raised water wall belongs to the ocean node, not to this one, so it
## outlives the player who raised it: someone disconnecting (or otherwise being
## despawned) mid-hold would leave a wall standing in the pool with nobody
## holding it and no input left running to drop it.
func _exit_tree() -> void:
	if _ocean and _ocean.has_method("stop_water_wall"):
		_ocean.stop_water_wall(self)

## True when this body is the one THIS game window drives: reads input, owns the
## camera, writes the GUI, and decides its own stamina and death. Everything
## else is somebody else's player, mirrored in from the network.
##
## Also true in solo play with no connection at all -- with no peer,
## get_unique_id() is 1 and so is the default authority -- so gating on this
## doesn't break running the game without hosting.
func _is_local() -> bool:
	return is_multiplayer_authority()

func _ready() -> void:
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

	# What side we're on, if the roster already knows. The host assigns teams
	# and broadcasts the table (see net.gd's _teams), which may land either
	# before or after this body exists -- if it arrived first, this picks it up
	# here; if it arrives later, net_sync_roster() pushes it onto us instead.
	# Covering both orders is why this asks rather than waiting to be told.
	#
	# _owner_peer > 0 only: a hand-placed decorative body (menu.tscn's
	# MenuPlayer) isn't in the roster at all and keeps whatever team the scene
	# set on it.
	if _owner_peer > 0:
		var assigned := Net.team_of(_owner_peer)
		if assigned >= 0:
			team = assigned

	# Kickboard rig + stat buffs if is_lifeguard was baked on for this
	# instance -- deferred to here rather than applied straight from
	# is_lifeguard's own setter (see there) so the mesh swap only ever runs
	# once the whole subtree, blockbench_export included, genuinely exists.
	# Every body needs this, remote ones included: is_lifeguard is identical
	# across every peer's copy of a given player (it's baked into the scene,
	# not something that needs network sync), so this keeps their mesh and
	# the water_wall loop-mode fix below correct in every window, not just
	# their own.
	_apply_lifeguard_loadout()

	# Everything past here belongs to whoever is playing in THIS window: the one
	# cursor, the one camera, the one set of GUI bars. A body mirrored in from
	# another peer must not touch any of it.
	if not _is_local():
		_setup_remote_body()
		return

	# Saved camera/turning settings, before any of it gets used below --
	# camera_hover_height in particular has to land before _cam_pivot_height
	# is captured from it a few lines down.
	Settings.apply_to(self)

	# Free cursor, not locked to the window -- A/D turn the camera now (see
	# _physics_process), and water_power (press 1) aims wherever the cursor
	# actually is (see _mouse_aim_direction), which needs its on-screen
	# position, not a captured/hidden relative-motion pointer.
	#
	# Both skipped for a decorative player (take_over_camera = false): it has
	# no business touching the one shared mouse mode, and its camera rig stays
	# in the scene but not .current, so whatever fixed camera is actually
	# showing the view (e.g. the menu's) keeps it.
	if take_over_camera:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_camera.current = true
	else:
		# Not just "skip claiming it" -- actively give it up. Camera3D
		# auto-promotes itself to .current on entering the tree if nothing else
		# has claimed the slot yet, and that happens as this subtree enters the
		# tree, before this _ready() runs -- so by this point it may already
		# have stolen the view out from under whatever fixed camera (e.g. the
		# menu's) was supposed to own it. Explicitly disowning it here is what
		# actually stops that, not the absence of the line above.
		_camera.current = false

	# Place ourselves rather than waiting to be told where we are. The host sets
	# this same position when it spawns the body, but on a joining client that
	# value arrived too late -- physics had already started from the scene's
	# default (0, 0, 0), under the pool, and since we're our own authority we'd
	# then publish that to everyone. spawn_position is derived from the peer id
	# so it agrees with the host's answer without needing to be sent.
	if _owner_peer > 0:
		position = Net.spawn_position(_owner_peer)

	# Tell anyone who joins later where we actually are. The synchronizer only
	# gets a stationary body's position across once it changes, so a player who
	# joined while we stood still saw us stuck wherever our body happened to be
	# when they got their copy of it -- and it only corrected once we moved.
	#
	# _owner_peer > 0 only -- a decorative body like menu.tscn's MenuPlayer
	# counts as "local" too (its default authority of 1 happens to match
	# whichever peer is the host), but it's not part of the real networked
	# roster at all. Without this gate, a host idling on the menu would
	# register this RPC for MenuPlayer, and fire it at literally any client
	# that ever connects, regardless of what scene that client is on --
	# producing "Node not found: .../MenuPlayer" errors disruptive enough to
	# break the connection, since the RPC targets a path
	# (menu.tscn/.../MenuPlayer) that doesn't exist on a client already
	# switched to ocean1.tscn.
	if _owner_peer > 0 and not multiplayer.peer_connected.is_connected(_on_peer_joined):
		multiplayer.peer_connected.connect(_on_peer_joined)

	# Drive the bars' ranges from the real stat maxima. They're authored in the
	# scene with their own max_value, which silently drifts from the stats they
	# show: stamina_bar shipped with max_value 10 against max_stamina 100, so
	# the bar hit full at a tenth of a tank and sat pinned there for the other
	# nine tenths. Draining read as a bar that clung to full and then dropped
	# out in the last two seconds, and refilling as a bar that snapped full
	# almost instantly -- both about ten times faster than the stat actually
	# moves. Setting it here means retuning max_stamina can't desync the bar.
	if gui:
		var stamina_bar: Range = gui.get_node_or_null("stamina_bar")
		if stamina_bar:
			stamina_bar.max_value = max_stamina
		var momentum_bar: Range = gui.get_node_or_null("momentum_bar")
		if momentum_bar:
			momentum_bar.max_value = max_momentum

	_underwater_mat = ShaderMaterial.new()
	_underwater_mat.shader = load("res://water/underwater.gdshader")

	# Detach the camera rig from the body so it can lag behind and drift into
	# place like a drone tracking its subject, instead of being welded 1:1 to
	# the body's every move (see _process for the actual catch-up lerp).
	# Deferred: reparenting synchronously from inside _ready() can leave the
	# node briefly reporting !is_inside_tree() to the current frame's process
	# pass; call_deferred runs it after the tree finishes settling instead.
	# Was _cam_pivot.position.y (the node's own baked transform) -- now driven
	# by the export instead, so Settings.apply_to() above (and Settings'
	# "camera arc" row) actually has somewhere to land.
	_cam_pivot_height = camera_hover_height
	call_deferred("_detach_camera_rig")
	_update_camera_pitch()

## Applies (or reverts) every lifeguard buff to match is_lifeguard: the
## kickboard rig and the stat numbers documented on is_lifeguard's own export
## above. Safe to call repeatedly and in either direction -- both branches
## always write every field rather than only touching what's different from
## the other, so there's no stale leftover from whichever state was active
## before.
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

## Swaps blockbench_export for the lifeguard rig (mesh/lifeguard.glb, kickboard
## included) or back to the normal one (mesh/character.glb), matching
## is_lifeguard. Only ever called once the whole scene subtree genuinely
## exists (see _ready() and is_lifeguard's setter) -- both meshes share every
## node name down to individual mesh parts (same Blockbench rig, re-exported),
## so the kickboard's presence is the only thing that tells an already-swapped
## lifeguard body apart from a normal one.
func _apply_mesh_for_lifeguard() -> void:
	var old := get_node_or_null("blockbench_export")
	if not (old and old.has_node("kickboard") == is_lifeguard):
		if old:
			remove_child(old)
			old.free()
		var mesh: Node3D = (_LIFEGUARD_MESH if is_lifeguard else _CHARACTER_MESH).instantiate()
		mesh.name = "blockbench_export"
		# Matches player.tscn's own baked transform for this node exactly --
		# both rigs were modeled/exported at the same scale and origin offset.
		mesh.transform = Transform3D(Basis().scaled(Vector3.ONE * 0.5), Vector3(0.0, -1.0725327, 0.0))
		add_child(mesh)
		_anim_player = get_node_or_null("blockbench_export/AnimationPlayer")
		# _movement_anim_state tracks what's playing on a SPECIFIC
		# AnimationPlayer instance -- a fresh one from the swap has never
		# played anything, regardless of what the old one was showing, so a
		# stale value here would make play_anim() think its target clip is
		# already running and skip triggering it, leaving the new rig frozen
		# on its bind pose. This is the live test_lifeguard_key toggle path,
		# not just a theoretical one -- see net.gd's _toggle_local_lifeguard().
		_movement_anim_state = -1
	# Unconditional, not just on the swapped branch above: a freshly-swapped
	# AnimationPlayer needs it applied fresh (it's a whole new set of Animation
	# resource instances), and the never-swapped case still needs it once, same
	# as before this function existed.
	_fix_animation_loop_modes()
	# Likewise unconditional: a swapped-in rig arrives with the untouched
	# imported material on every surface, so the team kit has to be re-applied
	# to it. (Swapping between the normal and lifeguard rig with
	# test_lifeguard_key is a live path, not a theoretical one.)
	_apply_team_colors()


## Paints this body in its team's colours by rebuilding each surface's albedo
## texture with every white texel replaced, then hanging the result on a
## surface override.
##
## A texture rewrite rather than a custom shader on purpose: the imported
## materials are alpha-MASK and double-sided, and a spatial shader would have
## to reproduce all of that (plus the whole lighting model) to look identical.
## Duplicating the imported StandardMaterial3D and swapping only its
## albedo_texture keeps every other imported setting exactly as authored.
##
## Cheap despite running per body: the atlases are 16x16 (256 texels), and
## _tinted_texture() caches per source-texture-and-team, so a full lobby of
## players on two teams builds at most a handful of tiny textures between them.
func _apply_team_colors() -> void:
	var rig := get_node_or_null("blockbench_export")
	if rig == null:
		return
	var color: Color = _TEAM_COLORS.get(team, _TEAM_COLORS[Team.RED])
	for mesh_inst in _mesh_instances_in(rig):
		if mesh_inst.mesh == null:
			continue
		for surface in mesh_inst.mesh.get_surface_count():
			# Read the material off the MESH RESOURCE, never the active one.
			# get_active_material() would resolve to the override this
			# function installed on a previous call, whose white texels are
			# already painted -- so switching a body from one team to the
			# other would find no white left to repaint and silently keep the
			# old colour. The mesh's own material is the untouched import, so
			# every call re-tints from the same clean source and lands on the
			# right colour no matter how many times the team changes.
			var base := mesh_inst.mesh.surface_get_material(surface)
			if not (base is StandardMaterial3D) or base.albedo_texture == null:
				continue
			var tinted := _tinted_texture(base.albedo_texture, color)
			if tinted == null:
				continue
			var mat: StandardMaterial3D = base.duplicate()
			mat.albedo_texture = tinted
			mesh_inst.set_surface_override_material(surface, mat)


## Every MeshInstance3D at or under `node`. The rigs nest their parts several
## levels deep (and differ between the two meshes), so this walks rather than
## assuming any particular layout.
func _mesh_instances_in(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_mesh_instances_in(child))
	return found


## Cache of recoloured atlases, keyed by source texture + team colour, shared
## by every player body in the scene. Static so two bodies on the same team
## reuse one texture instead of each building (and each keeping alive) their
## own identical copy.
static var _tint_cache: Dictionary = {}

## A copy of `source` with every near-white texel replaced by `color`.
## Returns null if the source image can't be read.
static func _tinted_texture(source: Texture2D, color: Color) -> ImageTexture:
	var key := [source.get_rid(), color]
	if _tint_cache.has(key):
		return _tint_cache[key]

	var img := source.get_image()
	if img == null:
		return null
	img = img.duplicate()
	# The atlases import as compressed VRAM textures (see the .import files);
	# get_pixel/set_pixel don't work on a compressed image, so flatten it to a
	# plain uncompressed format first.
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	img.convert(Image.FORMAT_RGBA8)

	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a > 0.0 and minf(minf(px.r, px.g), px.b) >= _TEAM_WHITE_CUTOFF:
				# Keep the source alpha: the materials are alpha-MASK, so
				# overwriting it here would punch holes in (or fill in) parts
				# of the rig that rely on it.
				img.set_pixel(x, y, Color(color.r, color.g, color.b, px.a))

	var tex := ImageTexture.create_from_image(img)
	_tint_cache[key] = tex
	return tex

## water_wall is authored to loop for as long as it's held, and (on
## mesh/character.glb) so are the movement cycles in _CHARACTER_LOOP_ANIMS --
## but glTF import always bakes every clip in at LOOP_NONE regardless of what
## Blockbench's own loop setting was (that authoring-time setting has nowhere
## to go in the glTF format, so it can never survive export), so both need it
## set explicitly here instead. water_power/water_attack (and, deliberately,
## every clip on mesh/lifeguard.glb but water_wall) stay LOOP_NONE -- hold on
## last frame -- on purpose; see is_lifeguard and _play_water_action_anim().
## Called from _apply_mesh_for_lifeguard() (both at _ready() and on a live rig
## swap), since a swapped-in rig comes with its own separate copy of every
## Animation resource that hasn't had this fix applied yet.
func _fix_animation_loop_modes() -> void:
	if not _anim_player:
		return
	var loop_names: Array[String] = ["water_wall"]
	if not is_lifeguard:
		loop_names += _CHARACTER_LOOP_ANIMS
	for anim_name in loop_names:
		if _anim_player.has_animation(anim_name):
			_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

## Turns this body into a puppet of the peer that owns it. Its transform comes
## from the MultiplayerSynchronizer, so local physics must not fight the
## incoming values -- freezing stops gravity, buoyancy and drag from dragging
## it off the position its owner reported.
##
## FREEZE_MODE_KINEMATIC rather than STATIC: a frozen-kinematic body still
## shoves what it runs into as it's moved, so on the host a remote swimmer
## bumping PushCube pushes it for real instead of passing through. The cube's
## physics live on the host (see ocean1.tscn's synchronizer), which is exactly
## where that collision needs to happen.
##
## The camera rig goes entirely: there's one camera per window and it belongs
## to the local player, so somebody else's body has no use for a SpringArm and
## a Camera3D following it around.
func _setup_remote_body() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	if is_instance_valid(_cam_pivot):
		_cam_pivot.queue_free()

func anim_name_to_string(anim_name: AnimationState) -> String:
	# Looks up the string by enum key; falls back to empty string if missing
	return ANIM_MAP.get(anim_name, "")

## Used to compare against _movement_anim_state (see there) instead of
## AnimationPlayer.current_animation directly, which reads as "" once a
## LOOP_NONE clip finishes and holds -- exactly the case play_anim() has to
## tell apart from "nothing has ever played".
func play_anim(anim_state: AnimationState) -> void:
	if not _anim_player:
		return
	if _movement_anim_state == anim_state:
		return
	_movement_anim_state = anim_state
	if anim_state == AnimationState.SWIM_UP:
		# Start it from the top at a sane rate; _apply_swim_up_anim_speed()
		# (called every frame from _anim_change) then fits it to the wind-up.
		#
		# This used to read `_anim_player.play("swim_up", mult)`, which never
		# changed the speed at all: play()'s second argument is custom_blend,
		# not custom_speed, so the multiplier was being spent on a blend time
		# and the clip always ran at 1.0. The ratio was upside down too --
		# stretching a clip over a longer wind-up needs clip_length / time,
		# not time / clip_length.
		_anim_player.speed_scale = 1.0
		_anim_player.play("swim_up")
		_apply_swim_up_anim_speed()
	else:
		# Anything else runs at its authored rate. speed_scale is a property of
		# the whole AnimationPlayer, so without this reset the wind-up's last
		# speed would carry straight into the next clip.
		_anim_player.speed_scale = 1.0
		_anim_player.play(anim_name_to_string(anim_state))

## Fires a one-shot animation for water_power/water_attack -- authored to
## hold on its last frame -- and keeps it in control of the AnimationPlayer
## (see the lock check in _anim_change()) until movement_state actually
## changes to something else, so the landing pose gets to read as a beat
## instead of snapping straight back to the movement animation next frame.
func _play_water_action_anim(anim_name: String) -> void:
	if not _anim_player or not _anim_player.has_animation(anim_name):
		return
	# speed_scale belongs to the whole AnimationPlayer, and the swim_up
	# wind-up drives it well away from 1.0 (see _apply_swim_up_anim_speed).
	# These clips can interrupt a wind-up mid-stroke, so without this reset
	# they'd inherit whatever rate it had reached and play in slow motion.
	_anim_player.speed_scale = 1.0
	_anim_player.play(anim_name)
	_action_anim_lock_movement_state = movement_state
	# This clip now owns the AnimationPlayer instead of play_anim()'s own
	# bookkeeping -- invalidate it so _anim_change() unconditionally
	# re-asserts control (even if movement_state happens to already equal
	# whatever it was before this fired) the next time it resumes.
	_movement_anim_state = -1

## Starts/keeps the looping water_wall animation in control of the
## AnimationPlayer for as long as it's held; see _stop_water_wall_anim() for
## release. Safe to call every held frame -- only calls play() once.
func _play_water_wall_anim() -> void:
	if not _anim_player or not _anim_player.has_animation("water_wall"):
		return
	if _anim_player.current_animation != "water_wall":
		# Same reset, same reason as _play_water_action_anim(): a wind-up
		# interrupted by raising the wall must not hand its playback rate over.
		_anim_player.speed_scale = 1.0
		_anim_player.play("water_wall")
	_wall_anim_active = true
	_movement_anim_state = -1 # same reasoning as _play_water_action_anim()

## Releases water_wall's hold on the AnimationPlayer so _anim_change() picks
## the movement animation back up next frame. Safe to call when it isn't
## active (player.gd calls it unconditionally every frame the key isn't held).
func _stop_water_wall_anim() -> void:
	_wall_anim_active = false

func _detach_camera_rig() -> void:
	# Deferred a frame by _ready, so the body can be gone by the time this runs:
	# joining a game clears the solo player that was spawned at startup, and
	# this call was already queued against it. Reparenting then passes a null
	# parent and reads a transform off a node that's no longer in the tree.
	if not is_inside_tree() or not is_instance_valid(_cam_pivot):
		return
	# The scene root, NOT get_parent(). The player used to sit directly under
	# Main so those were the same node, but players are spawned under "Players"
	# now -- and that's the node the MultiplayerSpawner watches, so parking a
	# camera rig in it means adding an unspawnable child to a replicated list.
	var root := get_tree().current_scene
	if root:
		_cam_pivot.reparent(root, true)

func _process(delta: float) -> void:
	# Animation runs for every body, local or not: movement_state is replicated
	# (see player.tscn's SceneReplicationConfig), so a remote swimmer animates
	# through exactly the same _anim_change() the local one does, off the state
	# its owner broadcast.
	if ANIMATE_PLAYER:
		_anim_change()

	# The camera, the cursor and the shake are per-window, so they only make
	# sense for the body this window is actually playing.
	if not _is_local():
		return

	if CONTROL_CAMERA:
		_camera_pivot_change(delta)

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_shake_change(delta)
	_update_revive_prompt()

## Decaying camera shake, driven off h_offset/v_offset rather than the camera's
## rotation or position: _camera_pivot_change already owns rotation.x, and the
## SpringArm3D rewrites the camera's position every frame to hold it at arm's
## length, so anything written there is gone by the next frame. The offsets are
## the one channel nothing else touches. Amplitude falls off linearly to zero
## and then snaps the offsets back to exactly 0, so a shake can't leave the
## camera parked slightly off-centre.
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

## Kick off a camera shake: `strength` in camera-offset units (small -- 0.05 is
## a nudge, 0.3 is a hit), decaying to nothing over `duration` seconds.
func shake_camera(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_total = maxf(duration, 0.001)
	_shake_left = _shake_total

func _anim_change() -> void:
	if movement_state == MovementState.DODGE:
		return # TODO handle in dodge functions
	if not _anim_player:
		return

	# Out cold: the death animation holds on its last frame and nothing should
	# take the body back off it. This has to be checked here rather than left to
	# the action lock below, because net_death sets movement_state to IDLE --
	# so without it the next frame would play "idle" straight over the top of
	# the death pose. Reviving clears _unconscious and hands control back.
	if _unconscious:
		return

	# water_wall (looping) and water_power/water_attack (hold on last frame)
	# are playing themselves directly -- see _play_water_wall_anim() and
	# _play_water_action_anim() -- so leave the AnimationPlayer alone instead
	# of stomping them with the movement-driven animation below.
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
			# Every frame, not just on the state change: the wind-up it's being
			# fitted to keeps moving (see _apply_swim_up_anim_speed), and
			# play_anim() above returns early once SWIM_UP is already the
			# current state, so this is the only thing still tracking it.
			_apply_swim_up_anim_speed()
		MovementState.SWIM:
			play_anim(AnimationState.SWIM)
		MovementState.GLIDE:
			play_anim(AnimationState.GLIDE)
		MovementState.WALK:
			play_anim(AnimationState.WALK)
		MovementState.JUMP:
			play_anim(AnimationState.JUMP)


# ---------------------------------------------------------------------------
# Water moves over the network
# ---------------------------------------------------------------------------
## Which move net_cast_water_move is carrying. Sent as an int rather than
## calling three near-identical RPCs, so there's one path to keep in step.
enum WaterMove { POWER, ATTACK }

## Fires a one-shot water move on every peer. Only the local player ever calls
## this -- the input that reaches it is already gated on _is_local().
##
## Sends the move, the origin and the aim, exactly as much as another peer
## needs to reproduce the wave; nothing about the resulting hit travels, since
## each peer works that out (or deliberately doesn't) in net_cast_water_move.
func _cast_water_move(kind: WaterMove, origin: Vector3, aim: Vector3, strength: float) -> void:
	if Net.is_online():
		# call_local, so this covers us too -- no separate local call.
		rpc("net_cast_water_move", kind, origin, aim, strength)
	else:
		net_cast_water_move(kind, origin, aim, strength)

@rpc("any_peer", "call_local", "reliable")
func net_cast_water_move(kind: WaterMove, origin: Vector3, aim: Vector3, strength: float) -> void:
	if _ocean == null:
		return
	# Everyone draws the wave; only the peer that cast it resolves what it hit.
	# _is_local() is true here exactly on the caster's own machine, because this
	# runs on the *caster's* body on every peer.
	var apply_hits := _is_local()
	# The damage range comes from THIS node's own stats -- a lifeguard's
	# buffed water_power_damage_max/water_attack_damage_max, read here rather
	# than threaded through the RPC, because self is always the caster's own
	# body (that's what call_local + running "on the caster's body on every
	# peer" means -- see the comment above), and is_lifeguard is identical on
	# every peer's copy of it already, no sync needed.
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

## The wall is held rather than fired, so it re-sends every frame it's up
## instead of once. Unreliable on purpose: at 60 sends a second a dropped
## packet is corrected by the next one a frame later, and the ordering
## guarantees of a reliable channel would cost more than they're worth for
## what is really just "the wall is still here, at this spot".
func _cast_water_wall(origin: Vector3, aim: Vector3, strength: float) -> void:
	if Net.is_online():
		rpc("net_water_wall", origin, aim, strength)
	else:
		net_water_wall(origin, aim, strength)

@rpc("any_peer", "call_local", "unreliable")
func net_water_wall(origin: Vector3, aim: Vector3, strength: float) -> void:
	if _ocean and _ocean.has_method("start_water_wall"):
		# `self` keys the wall to this player, so two people holding walls at
		# once get one each instead of fighting over a shared one.
		_ocean.start_water_wall(origin, aim, strength, self)
	_play_water_wall_anim()

## Dropping the wall is reliable -- unlike the per-frame updates above there's
## no follow-up packet to correct a lost one, and losing this would strand a
## wall standing in the pool with nobody holding it.
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

## Someone new turned up: send them our current state directly, so they don't
## have to wait for us to move before their copy of us is in the right place.
## Only the peer that owns this body is subscribed (see _ready), so exactly one
## peer answers for it.
func _on_peer_joined(id: int) -> void:
	if not _is_local():
		return
	rpc_id(id, "net_sync_state", position, rotation, movement_state, _unconscious)

## Current state of a body, pushed to a peer that just joined. Everything here
## is already replicated continuously -- this exists purely to seed the initial
## value, which the synchronizer alone doesn't reliably deliver for a body that
## isn't moving.
@rpc("any_peer", "reliable")
func net_sync_state(pos: Vector3, rot: Vector3, state: MovementState, out_cold: bool) -> void:
	# Never let a late packet stomp the body we're actually driving.
	if _is_local():
		return
	position = pos
	rotation = rot
	movement_state = state
	if out_cold and not _unconscious:
		net_death()

## Knockback, applied where this body's physics actually run. Called by
## ocean_fluid_bridge's _knockback (via _send_to_owner) on the peer that owns
## this player, since a remote copy is frozen and would ignore the impulse.
@rpc("any_peer", "reliable")
func net_apply_impulse(impulse: Vector3) -> void:
	if _is_local():
		apply_central_impulse(impulse)


func _camera_pivot_change(delta: float) -> void:
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
	if not gui:
		return
	gui.get_node("stamina_bar").value = stamina
	gui.get_node("momentum_bar").value = momentum

func _stamina_change(delta: float) -> void:
	# Bone dry -- not even wading -- so there's no water to be tired from.
	# Recover instead of draining, same as standing in the shallow end.
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

## Called by ocean_fluid_bridge.gd (_apply_hit_damage) when a water_power or
## water_attack wave lands on this player -- water_wall never calls this, it
## has no hit detection at all. Immediate stamina hit, on top of (not
## instead of) the normal per-tick drain/recovery in _stamina_change().
## Duck-typed from the ocean side (has_method("take_stamina_damage")), so
## anything that wants to be hurt by a wave just needs this one method.
## Holding up a water wall (_water_wall_up) cuts whatever gets through by
## water_wall_block_reduction -- 50% for a normal player, 90% for a lifeguard
## blocking with the kickboard (see is_lifeguard).
##
## An @rpc so the peer that landed the hit can call it on the peer that got
## hit (ocean_fluid_bridge routes it there via _send_to_owner). Stamina and the
## wall state both live on the owning peer, so the reduction has to be decided
## here rather than by whoever threw the wave.
@rpc("any_peer", "reliable")
func take_stamina_damage(amount: float) -> void:
	if _water_wall_up:
		amount *= water_wall_block_reduction
	stamina = clampf(stamina - amount, 0.0, max_stamina)
	if stamina <= 5.0:
		_death()

func _input(event: InputEvent) -> void:
	# Keystrokes in this window drive this window's player and nobody else's --
	# without this, one keypress would dodge every body in the pool at once.
	if not _is_local():
		return
	if _unconscious:
		return
	# Nothing lands before the countdown finishes -- not moves, not the revive
	# key, not the debug death key. Gated here at the source (the same place
	# _unconscious is) rather than per-action downstream, so a new action added
	# later is locked by default instead of having to remember to opt in.
	if movement_locked:
		return
	detect_death(event)
	# Reachable only while conscious, thanks to the _unconscious guard above --
	# which is exactly right: a lifeguard who's out cold themselves can't pick
	# anyone up. _revive_target() enforces the same rule again on its own, so
	# the prompt and the key never disagree.
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
		_movement_anim_state = -1 # same reasoning as _play_water_action_anim()
	_dodge(Vector3.LEFT)

func _dodge_right() -> void:
	if ANIMATE_PLAYER:
		_anim_player.play("dodge_right")
		_movement_anim_state = -1
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

## A jump off solid ground, triggered by the jump action. Only works standing
## in the shallow end or bone dry on the deck (a push off solid ground, same
## reasoning as _dodge -- nothing to push off in open water), and gated by
## jump_cooldown so it can't be chained. Spends the *entire* momentum stat on
## launch -- the more you had going in, the higher you go -- so it also
## doubles as a hard reset: you land with none of your old speed left.
func _jump(on_ground: bool) -> void:
	if not on_ground or momentum <= 0.0 or _jump_cooldown_timer > 0.0:
		return
	_jump_cooldown_timer = jump_cooldown
	# Diminishing returns on momentum: the exponent (< 1) flattens the curve, so
	# arriving at full tilt jumps higher than arriving at half, but nowhere near
	# twice as high. jump_speed is the launch at full momentum, in m/s, so the
	# ceiling is a real number you can reason about instead of falling out of
	# max_momentum -- retuning momentum no longer silently retunes the jump.
	var t := clampf(momentum / max_momentum, 0.0, 1.0)
	linear_velocity.y = jump_speed * pow(t, jump_momentum_exponent)
	momentum = 0.0
	movement_state = MovementState.JUMP

## The strength a water_power cast fires at right now: 1.0 baseline (a cast
## at zero momentum is unchanged from before this existed), plus a
## diminishing-returns bonus from banked momentum -- same curve shape as
## _jump()'s momentum -> launch height, just applied to a wave instead. Reads
## momentum but doesn't spend it -- the caller does that (see the water_power
## block above), all at once, the same way _jump() spends it on a launch:
## you're cashing in what you've built, not just consulting it.
##
## ocean_fluid_bridge.gd's send_wave() clamps whatever strength it's handed to
## [0.3, 4.0] regardless, so this can't accidentally exceed that ceiling no
## matter how the two exports above are tuned.
func _water_power_strength() -> float:
	var t := clampf(momentum / max_momentum, 0.0, 1.0)
	return 1.0 + water_power_momentum_bonus * pow(t, water_power_momentum_exponent)

## Sets the camera's rotation.x straight to the baked overhead tilt, with no
## smoothing. Used once at startup so the camera doesn't visibly lerp in from
## rotation 0 on the first frame; every frame after that, _process settles it
## toward this same target smoothly instead. Fixed, not mouse-driven -- the
## mouse doesn't touch the camera at all now, it's a pure aim pointer.
func _update_camera_pitch() -> void:
	_camera.rotation.x = deg_to_rad(default_camera_pitch_deg)

## Blacking out: stamina hit zero. Control is gone and the body goes limp --
## it keeps floating, it just isn't swimming any more -- while the ear ringing
## comes up and the eyelids fall shut over the view.
##
## The _unconscious latch is load-bearing, not defensive. _stamina_change tests
## `stamina <= 0.0` every physics tick, so this used to re-enter 60 times a
## second: play() restarted the ringing from frame 0 before a single frame of
## it could sound (a buzz, not a ring), and every tick stacked another tween
## onto the same shader parameter, so dozens of them fought over `progress` and
## the lids juddered instead of closing.
## Only the peer that owns this body decides it has died -- its stamina lives
## there (see take_stamina_damage) -- and then tells everyone, so the body goes
## limp in every window rather than only in its owner's.
func _death() -> void:
	if _unconscious:
		return
	if Net.is_online():
		# call_local, so this covers us as well as everyone else.
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
	# Stop taking input at the source, rather than only ignoring it downstream:
	# _input stops being called at all, and _physics_process bails before it
	# reads a single action. revive() turns it back on.
	set_process_input(false)

	# That may have been the last one standing on this side. Told rather than
	# polled, and told from here specifically because this runs on EVERY peer
	# with _unconscious already set -- so whoever is the authority is looking
	# at a complete, current picture of who's up. Net itself decides whether
	# it's allowed to act on it (see on_player_down).
	#
	# Deferred, and that is not cosmetic. Called straight through, it runs
	# BEFORE the rest of this function -- so a death that ends the round
	# triggers the end-of-round revive here, and then execution carries on
	# down this same function and blacks the screen out again on top of it,
	# leaving a body that is conscious but sitting behind fallen eyelids
	# playing a death animation. Deferring lets the death finish applying
	# first, so the revive has a settled state to undo.
	Net.call_deferred("on_player_down")

	# A wall left standing when its owner blacks out would hang in the pool
	# with nobody holding it up, since the input that drops it stops running.
	if _water_wall_up:
		_water_wall_up = false
		if _ocean and _ocean.has_method("stop_water_wall"):
			_ocean.stop_water_wall(self)
	# Clear the wall's animation hold too, whether or not a wall was up: it
	# outranks the movement animation in _anim_change, so leaving it set would
	# keep the body looping water_wall instead of going limp.
	_stop_water_wall_anim()

	# Dropping. Played on every peer, not just the dying one -- watching
	# somebody go under is the whole point of broadcasting a death. Imported
	# from glTF as LOOP_NONE, so it holds on its last frame by itself, and
	# _anim_change leaves it there for as long as _unconscious is set.
	if _anim_player and _anim_player.has_animation("death"):
		_anim_player.play("death")
		_movement_anim_state = -1 # same reasoning as _play_water_action_anim()

	# Past here is what blacking out looks like from behind your own eyes: the
	# ear ringing and the lids falling. Somebody else going under doesn't black
	# YOUR screen out -- you just watch their body go limp.
	if not _is_local():
		return

	if _muffled_player:
		_muffled_player.play()

	if _eyelid and _eyelid.material:
		# 0.0 is a wide open eye, 1.0 fully shut (see eye_closing.gdshader --
		# `progress` drives the murk, the tunnel and the lids together).
		# Starting the tween at 0.5 snapped them half closed on the first frame
		# before animating; starting from open lets them actually fall.
		_eyelid.material.set_shader_parameter("progress", 0.0)
		# Half the ear-ringing clip, so the lids finish falling while the ring
		# is still going and the sound outlives the picture. Falls back to
		# blackout_time when there's no stream to measure (get_length() on a
		# null stream would take the whole function down with it).
		var _duration := blackout_time
		if _muffled_player and _muffled_player.stream:
			_duration = _muffled_player.stream.get_length() / 2
		_eyelid_tween = create_tween()
		# Linear on purpose. `progress` isn't one animation any more, it's the
		# clock the shader reads off, and it shapes each layer itself: the murk
		# slams in over the first cloud_ramp of it, the tunnel follows, the lids
		# hold until lid_delay and then fall. Easing this drove all three at
		# once -- a sine ease-in here, on top of the shader squaring it, left
		# the screen at 8% murk halfway through the blackout.
		_eyelid_tween.set_trans(Tween.TRANS_LINEAR)
		_eyelid_tween.tween_method(
			func(val: float) -> void:
				var curved := 1.0 - pow(1.0 - val, 5.0)
				_eyelid.material.set_shader_parameter("progress", curved),
			0.0,
			1.0,
			_duration)

## Coming to: the mirror of _death(). Eyes snap back open with a jolt through
## the camera, the ringing cuts, and control comes back.
##
## Called on a downed body by a lifeguard standing over it (see
## _try_revive_nearby()), and safe to call from anywhere else that should bring
## a player round -- a timer, a respawn point. No-op if already conscious.
##
## Broadcast for exactly the same reason _death() is: a body going limp has to
## go limp in every window, so a body sitting back up has to sit back up in
## every window too. Unlike _death(), the caller here is usually somebody
## ELSE's body (the lifeguard), which is fine -- an rpc() targets whatever node
## it's called on, and net_revive is "any_peer" so a peer that doesn't own this
## body is still allowed to trigger it.
func revive() -> void:
	if not _unconscious:
		return
	if Net.is_online():
		# call_local, so this covers us as well as everyone else.
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
	# The death clip holds on its last frame and _anim_change() refuses to
	# touch the AnimationPlayer at all while _unconscious (see there), so the
	# body is still frozen in the death pose right now. Clearing the latch
	# above hands control back, but play_anim() skips any clip it believes is
	# already running -- and _movement_anim_state still says "death" from
	# net_death(). Resetting it is what actually gets the body up off the
	# floor rather than leaving it limp but controllable.
	_movement_anim_state = -1
	# A double-tap registered before blacking out shouldn't cash in as a dodge
	# the instant control returns.
	last_a_press = -1000.0
	last_d_press = -1000.0

	# Past here is what coming round looks like from behind your own eyes --
	# the mirror of net_death()'s split. Watching somebody else get picked up
	# doesn't un-black YOUR screen.
	if not _is_local():
		return

	if _muffled_player:
		_muffled_player.stop()

	shake_camera(revive_shake_strength, revive_shake_time)

	if _eyelid and _eyelid.material:
		# Kill the close if it's still running, or the two tweens would drive
		# `progress` in opposite directions at once.
		if _eyelid_tween and _eyelid_tween.is_valid():
			_eyelid_tween.kill()
		# Snap open from wherever the lids actually are, not from a fixed value,
		# so reviving mid-close doesn't jump them shut first. Ease-out so they
		# fly open and settle rather than crawling.
		var from: float = _eyelid.material.get_shader_parameter("progress")
		_eyelid_tween = create_tween()
		_eyelid_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_eyelid_tween.tween_method(
			func(val: float) -> void:
				_eyelid.material.set_shader_parameter("progress", val),
			from,
			0.0,
			eyelid_open_time)

# ---------------------------------------------------------------------------
# Lifeguard revives
# ---------------------------------------------------------------------------
## The downed teammate this body could pick up right now, or null. Drives both
## the revive itself and the on-screen prompt (see revive_prompt.gd), so the
## prompt can never offer a revive that pressing the key wouldn't actually do
## -- there's one set of rules here, not two that have to be kept in step.
##
## Being a lifeguard is the whole job: a normal player standing on a teammate
## does nothing. Same team only, and you have to be conscious yourself.
func _revive_target() -> Node:
	if not is_lifeguard or _unconscious:
		return null
	var best: Node = null
	var best_dist := revive_range
	for other in get_tree().get_nodes_in_group("player"):
		if other == self or not is_instance_valid(other):
			continue
		# Duck-typed, matching how the rest of this file talks to other bodies:
		# anything in the "player" group that can be out cold and has a side.
		if not ("_unconscious" in other and "team" in other):
			continue
		if not other._unconscious or other.team != team:
			continue
		var dist := global_position.distance_to(other.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = other
	return best


## Picks up whoever _revive_target() nominated. Split from the input handler so
## the rules live in one place and can be tested without synthesising a key
## press.
func _try_revive_nearby() -> void:
	var target := _revive_target()
	if target:
		target.revive()


## Builds the floating "[R] Revive" tag for THIS window, once, the first time
## it's actually needed. Lazy rather than made in _ready() because most bodies
## never need one: only the local player has a camera to unproject against,
## and only a lifeguard will ever have a target to point it at.
##
## Parented to the HUD CanvasLayer so it draws over the 3D view. `gui` can be
## absent entirely (a decorative body in a scene with no HUD -- see the comment
## on that var), in which case there's simply no prompt, same as every other
## HUD feature here.
func _ensure_revive_prompt() -> Node:
	if is_instance_valid(_revive_prompt):
		return _revive_prompt
	if gui == null:
		return null
	_revive_prompt = _REVIVE_PROMPT.instantiate()
	gui.add_child(_revive_prompt)
	return _revive_prompt


## Keeps the prompt pointed at whoever we could pick up right now. Called every
## frame for the local player only (see _process): it's a per-window overlay,
## and _revive_target() is the same check the revive key runs, so what's on
## screen and what the key does can't drift apart.
func _update_revive_prompt() -> void:
	var target := _revive_target()
	# Don't build the prompt just to be told there's nobody to revive -- a
	# normal (non-lifeguard) player would otherwise still get one made for it
	# on its first frame and keep it forever, hidden.
	if target == null and not is_instance_valid(_revive_prompt):
		return
	var prompt := _ensure_revive_prompt()
	if prompt:
		prompt.show_for(target, _camera)


## Turns the body (and the camera, which follows its yaw -- see _process)
## while A/D are held, at turn_speed rad/s. Replaces the old mouse-yaw and the
## old A/D strafe -- these keys steer now instead of sidestepping.
func _turn_from_input(delta: float) -> void:
	var turn := Input.get_axis("left", "right")
	if turn == 0.0:
		_turn_hold_time = 0.0
		return

	var rate := turn_speed
	if exponential_turn_sensitivity:
		# Same exponential-approach idiom as camera_turn_speed/
		# camera_pitch_speed above (1.0 - exp(-t/tau)) -- ramps from a
		# standing start up toward the full turn_speed instead of applying it
		# instantly, so tapping A/D nudges gently and holding it down builds
		# into a full turn.
		_turn_hold_time += delta
		rate *= 1.0 - exp(-_turn_hold_time / turn_ramp_time)
	else:
		_turn_hold_time = 0.0

	rotate_y(-turn * rate * delta)

## Bleeds off whatever drift is left so the body coasts to a stop instead of
## sailing on, while buoyancy keeps floating it at the surface. Applied
## directly rather than through _apply_central_force so they can't be silenced
## by a stale can_move, and buoyancy stays last for the force-ordering reason
## in _physics_process.
##
## Shared by the two states that take no input but are still in the water:
## blacked out (_unconscious) and waiting for the round to start
## (movement_locked).
func _drift_to_a_stop() -> void:
	var v := linear_velocity
	apply_central_force(
		Vector3(-v.x, 0.0, -v.z) * (water_linear_drag * 1.5) * mass)
	_apply_buoyancy(_submersion())


func _physics_process(delta: float) -> void:
	# A remote body is a puppet: its transform is replicated in from the peer
	# that owns it (see _setup_remote_body), and it's frozen so none of the
	# force/velocity work below could take effect anyway. Reading input for it
	# would also mean this window's keys driving somebody else's player.
	if not _is_local():
		return

	if _unconscious:
		# Limp body. Input is ignored -- no turning, no strokes, no momentum --
		# but the water carries on acting on it (see _drift_to_a_stop).
		_drift_to_a_stop()
		return

	if movement_locked:
		# Same treatment as a limp body, for a completely different reason:
		# the round hasn't started yet (see net.gd's countdown). Float on the
		# spot, take no input, but stay in the water properly rather than
		# hanging frozen above it or sinking through it.
		_drift_to_a_stop()
		return

	_turn_from_input(delta)

	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_jump_cooldown_timer = maxf(_jump_cooldown_timer - delta, 0.0)
	_water_power_cooldown_timer = maxf(_water_power_cooldown_timer - delta, 0.0)
	_water_attack_cooldown_timer = maxf(_water_attack_cooldown_timer - delta, 0.0)

	# Compute these once per tick; in_shallow_end() runs a raycast, so don't call
	# it (or _submersion) repeatedly below.
	var submersion := _submersion()
	var shallow := in_shallow_end()

	if Input.is_action_just_pressed("jump"):
		# Solid ground to push off: the shallow end's floor, or bone dry on the
		# deck -- either way there's something underfoot. Open water (swimming
		# or treading) has nothing to launch off, same reasoning as _dodge.
		_jump(shallow or submersion <= 0.0)

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
	# it starts at the surface height and can't be aimed up or down). Needs
	# actual water to draw on -- bone dry on the deck, there's nothing to shove
	# -- enough stamina banked to cover the cast, same gating as _dodge() --
	# and its cooldown spent, same reasoning as dodge/jump: no throwing
	# another one before your arms have recovered from the last.
	if submersion > 0.0 and Input.is_action_just_pressed("water_power") \
			and stamina >= water_power_stamina_cost \
			and _water_power_cooldown_timer <= 0.0 \
			and _ocean and _ocean.has_method("send_wave"):
		var aim := _mouse_aim_direction()
		var origin := global_position + aim * 1.0
		origin.y = _water_height()
		# The wave and its animation are raised on every peer from inside the
		# RPC, this one included -- see _cast_water_move.
		_cast_water_move(WaterMove.POWER, origin, aim, _water_power_strength())
		stamina -= water_power_stamina_cost
		_water_power_cooldown_timer = water_power_cooldown
		# Spent, not banked -- _water_power_strength() already read momentum to
		# compute the strength argument above (evaluated before the call), so
		# zeroing it here can't undersell the cast that's already on its way
		# out. Same all-or-nothing spend as _jump(): a big cast is a decision
		# to burn what you've built, not a free multiplier you keep afterward.
		momentum = 0.0

	# Water attack (water_attack action): close-range counterpart to water
	# power -- a much bigger, denser burst that barely travels, a shove right
	# in front of you rather than a lance across the pool. Same water-only,
	# stamina, and cooldown gating as water power, just cheaper on all three --
	# it's the low-commitment option.
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

	# Water wall (water_wall action, hold 3): raises a stationary wall of
	# water in front of the player and keeps it up -- and tracking the
	# player's aim -- for as long as the key stays held; letting go drops it.
	# Costs stamina continuously while held (steepest of the three, per
	# second rather than per cast), and running out cuts it off the same as
	# letting go. It's the one functional part of the move so far: while up,
	# take_stamina_damage() halves any hit that gets through -- the "defend"
	# half of the move, ahead of it actually blocking incoming waves.
	if submersion > 0.0 and Input.is_action_pressed("water_wall") and stamina > 0.0 \
			and _ocean and _ocean.has_method("start_water_wall"):
		var wall_aim := _mouse_aim_direction()
		var wall_origin := global_position + wall_aim * 1.2
		wall_origin.y = _water_height()
		_cast_water_wall(wall_origin, wall_aim, 1.0)
		_water_wall_up = true
		stamina -= water_wall_stamina_cost_per_second * delta
	elif _water_wall_up:
		# Only on the frame it actually drops, not every frame the key is idle:
		# this now goes out over the network, and re-sending "wall down" sixty
		# times a second to say nothing changed is pure traffic.
		_cast_water_wall_stop()
		_water_wall_up = false

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


## Seconds of wind-up actually left before momentum reaches the swim
## threshold, at the current stroke rate.
##
## Solved, not sampled -- and that distinction is the whole point. It's
## tempting to read _swim_up_animation_time() as "how long the wind-up takes",
## but it's an instantaneous pacing figure, not a duration: _swim() builds
## momentum at `momentum_needed_to_swim / _swim_up_animation_time() * k` per
## second, and _swim_up_animation_time() itself grows from 0.5 to 1.5 as
## momentum rises, so the rate keeps dropping the closer you get. Using it as a
## duration would badly overstate the time left near the threshold.
##
## Writing u = momentum / momentum_needed_to_swim, that gain rate is
##     du/dt = k / (0.5 + u)
## so integrating (0.5 + u) du from u to 1 gives the time to cover what's left:
##     remaining = (1 - u/2 - u^2/2) / k
## which is 1/k seconds from a standing start and exactly 0 at the threshold.
## (Checked against a numeric integration of the same gain loop.)
##
## k is the stroke scaling _swim() applies -- direction (forward strokes build
## slower) times the lifeguard's momentum_gain_mult -- cached in
## _swim_gain_scale so this can't disagree with what the physics actually did.
func _swim_up_time_remaining() -> float:
	if momentum_needed_to_swim <= 0.0:
		return 0.0
	var k := _swim_gain_scale * momentum_gain_mult
	if k <= 0.0:
		return 0.0
	var u := clampf(momentum / momentum_needed_to_swim, 0.0, 1.0)
	return (1.0 - u * 0.5 - u * u * 0.5) / k


## Paces the swim_up clip so it plays through exactly once over the wind-up,
## finishing as momentum hits the swim threshold and the swim cycle takes over.
##
## Re-evaluated every frame rather than set once when the state is entered,
## because the thing being fitted to keeps moving: k changes the moment you
## switch between forward and backward strokes, momentum decays if you stop,
## and the wind-up can be entered part-way through. Each frame it re-fits
## whatever is left of the clip to whatever is left of the wind-up, so it
## self-corrects instead of drifting.
##
## Drives speed_scale rather than play()'s custom_speed so it can be adjusted
## on an already-playing clip without restarting it. speed_scale is global to
## the AnimationPlayer, which is exactly why _anim_change() puts it back to 1.0
## for every other state -- otherwise the wind-up's speed would leak into the
## walk cycle the moment you climbed out of the pool.
func _apply_swim_up_anim_speed() -> void:
	if not _anim_player or not _anim_player.has_animation("swim_up"):
		return
	# Reads "" once a LOOP_NONE clip has finished and is holding its last
	# frame; nothing left to pace at that point.
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
	# Clamped: right at the threshold time_left goes to zero, and an unclamped
	# ratio would spike the last frames into a blur.
	_anim_player.speed_scale = clampf(
		clip_left / time_left, _SWIM_UP_MIN_SPEED, _SWIM_UP_MAX_SPEED)

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
		# momentum_gain_mult buffs both branches -- the kickboard doesn't care
		# whether you're still winding up or already past the swim threshold,
		# it just makes every stroke count for more either way.
		var gain_scale := forward_swim_gain_mult if input_dir.y < 0.0 else 1.0
		# Cached for _swim_up_time_remaining(), so the wind-up animation is
		# paced off the same stroke scaling the momentum actually built at
		# rather than a second guess at it.
		_swim_gain_scale = gain_scale
		var swim_up_time := _swim_up_animation_time()
		if swim_up_time > 0.0:
			momentum += momentum_needed_to_swim / swim_up_time * delta * gain_scale * momentum_gain_mult
		else:
			momentum += SWIM_GAIN * pow(1.0 - t, 2.0) * delta * gain_scale * momentum_gain_mult
		momentum = min(momentum, max_momentum)
	else:
		# Deep-water idle decay -- momentum_loss_mult is the kickboard's "lose
		# less in the deep end" half of the buff.
		momentum = move_toward(momentum, 0.0, SWIM_GAIN * delta * momentum_loss_mult)

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
		# momentum_loss_mult -- the other deep-water spot the kickboard's
		# "lose less" applies, alongside _swim()'s idle decay.
		momentum -= SWIM_GAIN * delta * momentum_loss_mult
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
