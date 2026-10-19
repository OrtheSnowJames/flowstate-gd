extends RefCounted

enum HandMode { NEUTRAL, ATTACK, SWIM }

const MIN_SWEEP := 0.18
const MIN_SPEED := 0.25
const MIN_ROW_DISTANCE := 0.1
const MIN_ROW_SPEED := 0.12
var _previous: Array = [null, null]
var _travel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _row_distance: Array[float] = [0.0, 0.0]
var _idle: Array[float] = [0.0, 0.0]
var _kind: Array[String] = ["", ""]
var _cooldown: Array[float] = [0.0, 0.0]


func reset() -> void:
	_previous = [null, null]
	_travel = [Vector3.ZERO, Vector3.ZERO]
	_row_distance = [0.0, 0.0]
	_idle = [0.0, 0.0]
	_kind = ["", ""]
	_cooldown = [0.0, 0.0]


static func hand_mode(left: Transform3D, right: Transform3D, previous := HandMode.NEUTRAL, left_point := Vector3.ZERO, right_point := Vector3.ZERO) -> HandMode:
	if not left.is_finite() or not right.is_finite():
		return HandMode.NEUTRAL
	var left_up := left.basis.y.normalized()
	var right_up := right.basis.y.normalized()
	var between := right.origin - left.origin
	between.y = 0.0
	# hands can be staggered and tilted without aiming at an exact point
	if between.length() >= 0.06:
		var holding := previous == HandMode.SWIM
		var tilted := maxf(left_up.y, right_up.y) < (0.85 if holding else 0.8)
		if _inward(left_up, right_up, between.normalized(), holding) or (tilted and _inward(left_point, right_point, between.normalized(), holding)):
			return HandMode.SWIM
	var upright := minf(left_up.dot(Vector3.UP), right_up.dot(Vector3.UP))
	if upright >= (0.5 if previous == HandMode.ATTACK else 0.65):
		return HandMode.ATTACK
	return HandMode.NEUTRAL


static func _inward(left: Vector3, right: Vector3, across: Vector3, holding: bool) -> bool:
	if not left.is_finite() or not right.is_finite() or left.is_zero_approx() or right.is_zero_approx():
		return false
	left = left.normalized()
	right = right.normalized()
	var margin := 0.3 if holding else 0.4
	return left.dot(across) >= margin and right.dot(-across) >= margin \
		and left.dot(right) <= 0.35 and maxf(absf(left.y), absf(right.y)) <= (0.85 if holding else 0.8)


func sample(hand: int, position: Vector3, touching_water: bool, tracked: bool, _movement: float, delta: float, heading := Basis.IDENTITY, mode := HandMode.ATTACK) -> Dictionary:
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
	var horizontal := Vector2(step.x, step.z).length()
	if mode == HandMode.SWIM:
		# rowing accepts a curved push and pull instead of exact cardinal directions
		if horizontal / delta >= MIN_ROW_SPEED and horizontal >= absf(step.y) * 0.4:
			kind = "stroke"
	elif step.length() / delta >= MIN_SPEED:
		if absf(step.x) > absf(step.z) * 1.4 and absf(step.x) > absf(step.y):
			kind = "wall"
		elif absf(step.z) > absf(step.x) and absf(step.z) > absf(step.y) * 0.7:
			if step.z < 0.0:
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
	if kind == "stroke":
		_row_distance[hand] += horizontal
	if (kind == "stroke" and _row_distance[hand] >= MIN_ROW_DISTANCE) or (kind == "wall" and _travel[hand].length() >= MIN_SWEEP):
		return _finish(hand)
	return result


func _finish(hand: int) -> Dictionary:
	var rowing := _kind[hand] == "stroke"
	var distance := _row_distance[hand] if rowing else _travel[hand].length()
	var result := {}
	if distance >= (MIN_ROW_DISTANCE if rowing else MIN_SWEEP) and not _kind[hand].is_empty() and _cooldown[hand] <= 0.0:
		result = {"kind": _kind[hand], "distance": distance, "direction": _travel[hand].normalized()}
		_cooldown[hand] = 0.18
	_clear(hand)
	return result


func _clear(hand: int) -> void:
	_travel[hand] = Vector3.ZERO
	_row_distance[hand] = 0.0
	_kind[hand] = ""
	_idle[hand] = 0.0


static func wave_strength(distance: float) -> float:
	return remap(clampf(distance, MIN_SWEEP, 1.2), MIN_SWEEP, 1.2, 0.5, 2.5)
