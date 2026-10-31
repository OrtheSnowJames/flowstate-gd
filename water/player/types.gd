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
	HURDLE,
	CANNON_BALL,
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
	HURDLE,
	CANNON_BALL,
}

enum WaterMove { POWER, ATTACK, PELT, COUNTER }
const WATER_POWER_RANGE := 7.0

const ANIM_MAP: Dictionary = {
	AnimationState.IDLE: "idle",
	AnimationState.TREAD: "tread",
	AnimationState.SWIM_UP: "swim_up",
	AnimationState.SWIM: "swim",
	AnimationState.GLIDE: "glide",
	AnimationState.DODGE_LEFT: "dodge_left",
	AnimationState.DODGE_RIGHT: "dodge_right",
	AnimationState.WALK: "walk",
	AnimationState.JUMP: "jump",
	AnimationState.HURDLE: "hurdle",
	AnimationState.CANNON_BALL: "cannon_ball",
}
