extends RefCounted

const SEQUENCE := ["a", "a", "b", "b", "left", "right", "left", "right"]
const STEP_TIMEOUT := 3.0
var _step := 0
var _elapsed := 0.0
var _a := false
var _b := false
var _sticks := [0, 0]


func reset() -> void:
	_step = 0
	_elapsed = 0.0
	_a = false
	_b = false
	_sticks = [0, 0]


func update(a: bool, b: bool, left_x: float, right_x: float, delta: float) -> bool:
	_elapsed += delta
	if _elapsed > STEP_TIMEOUT:
		_step = 0
	var inputs: Array[String] = []
	if a and not _a:
		inputs.append("a")
	if b and not _b:
		inputs.append("b")
	_a = a
	_b = b
	var axes := [left_x, right_x]
	for i in range(2):
		var direction := 0
		if absf(axes[i]) >= 0.65:
			direction = -1 if axes[i] < 0.0 else 1
		elif absf(axes[i]) > 0.25:
			direction = _sticks[i]
		# held buttons and stick jitter count only once
		if direction != 0 and direction != _sticks[i]:
			inputs.append("left" if direction < 0 else "right")
		_sticks[i] = direction
	if inputs.is_empty():
		return false
	_elapsed = 0.0
	if inputs.size() != 1:
		_step = 0
		return false
	if inputs[0] != SEQUENCE[_step]:
		_step = 1 if inputs[0] == "a" else 0
		return false
	_step += 1
	if _step == SEQUENCE.size():
		_step = 0
		return true
	return false
