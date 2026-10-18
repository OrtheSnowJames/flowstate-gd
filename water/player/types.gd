extends RefCounted

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

enum WaterMove { POWER, ATTACK, PELT, COUNTER }

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
