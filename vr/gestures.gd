extends RefCounted

enum HandMode { NEUTRAL, ATTACK, SWIM }

const MIN_SWEEP := 0.18
const MIN_SPEED := 0.25
var _previous: Array = [null, null]
var _travel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _idle: Array[float] = [0.0, 0.0]
var _kind: Array[String] = ["", ""]
var _cooldown: Array[float] = [0.0, 0.0]


func reset() -> void:
	_previous = [null, null]
	_travel = [Vector3.ZERO, Vector3.ZERO]
	_idle = [0.0, 0.0]
	_kind = ["", ""]
	_cooldown = [0.0, 0.0]


static func hand_mode(left: Transform3D, right: Transform3D, previous := HandMode.NEUTRAL) -> HandMode:
	if not left.is_finite() or not right.is_finite():
		return HandMode.NEUTRAL
	var between := right.origin - left.origin
	if between.length() < 0.1:
		return HandMode.NEUTRAL
	var left_up := left.basis.y.normalized()
	var right_up := right.basis.y.normalized()
	var inward := minf(left_up.dot(between.normalized()), right_up.dot(-between.normalized()))
	var upright := minf(left_up.dot(Vector3.UP), right_up.dot(Vector3.UP))
	if inward >= (0.5 if previous == HandMode.SWIM else 0.65):
		return HandMode.SWIM
	if upright >= (0.5 if previous == HandMode.ATTACK else 0.65):
		return HandMode.ATTACK
	return HandMode.NEUTRAL


func sample(hand: int, position: Vector3, touching_water: bool, tracked: bool, movement: float, delta: float, heading := Basis.IDENTITY, mode := HandMode.ATTACK) -> Dictionary:
	_cooldown[hand] = maxf(0.0, _cooldown[hand] - delta)
	if not tracked or mode == HandMode.NEUTRAL or delta <= 0.0 or delta > 0.15:
		_previous[hand] = null
		_clear(hand)
		return {}
	var previous = _previous[hand]
	_previous[hand] = position
	if previous == null:
		return {}
	var step: Vector3 = heading.inverse() * (position - previous)
	if step.length() > 0.35:
		_clear(hand)
		return {}
	if not touching_water:
		return _finish(hand)
	var kind := ""
	if step.length() / delta >= MIN_SPEED:
		if mode == HandMode.ATTACK and absf(step.x) > absf(step.z) * 1.4 and absf(step.x) > absf(step.y):
			kind = "wall"
		elif absf(step.z) > absf(step.x) and absf(step.z) > absf(step.y) * 0.7:
			if mode == HandMode.SWIM and ((movement < -0.2 and step.z > 0.0) or (movement > 0.2 and step.z < 0.0)):
				kind = "stroke"
			elif mode == HandMode.ATTACK and step.z < 0.0:
				kind = "wave"
	if kind.is_empty():
		_idle[hand] += delta
		return _finish(hand) if _idle[hand] >= 0.09 else {}
	var result := {}
	if kind != _kind[hand] or _travel[hand].dot(step) < 0.0:
		result = _finish(hand)
	_kind[hand] = kind
	_idle[hand] = 0.0
	_travel[hand] += step
	if kind != "wave" and _travel[hand].length() >= MIN_SWEEP:
		return _finish(hand)
	return result


func _finish(hand: int) -> Dictionary:
	var distance := _travel[hand].length()
	var result := {}
	if distance >= MIN_SWEEP and not _kind[hand].is_empty() and _cooldown[hand] <= 0.0:
		result = {"kind": _kind[hand], "distance": distance, "direction": _travel[hand].normalized()}
		_cooldown[hand] = 0.18
	_clear(hand)
	return result


func _clear(hand: int) -> void:
	_travel[hand] = Vector3.ZERO
	_kind[hand] = ""
	_idle[hand] = 0.0


static func wave_strength(distance: float) -> float:
	return remap(clampf(distance, MIN_SWEEP, 1.2), MIN_SWEEP, 1.2, 0.5, 2.5)
