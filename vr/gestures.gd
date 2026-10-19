extends RefCounted

const MIN_SWEEP := 0.18
const MIN_SPEED := 0.25
var _previous: Array = [null, null]
var _wet: Array[bool] = [false, false]
var _travel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _idle: Array[float] = [0.0, 0.0]
var _kind: Array[String] = ["", ""]
var _cooldown: Array[float] = [0.0, 0.0]


func reset() -> void:
	_previous = [null, null]
	_wet = [false, false]
	_travel = [Vector3.ZERO, Vector3.ZERO]
	_idle = [0.0, 0.0]
	_kind = ["", ""]
	_cooldown = [0.0, 0.0]


func sample(hand: int, position: Vector3, touching_water: bool, tracked: bool, delta: float, heading := Basis.IDENTITY) -> Dictionary:
	_cooldown[hand] = maxf(0.0, _cooldown[hand] - delta)
	if not tracked or not position.is_finite() or delta <= 0.0 or delta > 0.15:
		_previous[hand] = null
		_clear(hand)
		return {}
	var previous = _previous[hand]
	_previous[hand] = position
	# crossing the surface starts a new gesture instead of carrying an old one over
	if touching_water != _wet[hand]:
		_wet[hand] = touching_water
		_clear(hand)
		return {}
	if previous == null:
		return {}
	var step: Vector3 = heading.inverse() * (position - previous)
	if step.length() > 0.35:
		_clear(hand)
		return {}
	var kind := ""
	if step.length() / delta >= MIN_SPEED:
		if absf(step.x) > absf(step.z) * 1.4 and absf(step.x) > absf(step.y):
			kind = "stroke" if touching_water else "wall"
		elif absf(step.z) > absf(step.x) and absf(step.z) > absf(step.y) * 0.7:
			if touching_water and step.z < 0.0:
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
