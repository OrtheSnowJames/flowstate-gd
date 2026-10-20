extends RefCounted

const HAND_RADIUS := 0.12
const PUSH_STRENGTH := 120.0
var _previous: Array = [null, null]


func reset() -> void:
	_previous = [null, null]


func sample(cube, hand: int, at: Vector3, tracked: bool) -> bool:
	var previous = _previous[hand]
	_previous[hand] = at if tracked and at.is_finite() else null
	if _previous[hand] == null or previous == null or not is_instance_valid(cube):
		return false
	var impulse := contact_impulse(cube, previous, at)
	if impulse.is_zero_approx():
		return false
	cube.queue_contact_push(impulse)
	return true


static func contact_impulse(cube: RigidBody3D, from: Vector3, to: Vector3) -> Vector3:
	var motion := to - from
	if not from.is_finite() or not to.is_finite() or motion.length() > 0.6:
		return Vector3.ZERO
	var collision := cube.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled or not collision.shape is BoxShape3D:
		return Vector3.ZERO
	var inverse := collision.global_transform.affine_inverse()
	var half: Vector3 = collision.shape.size * 0.5
	var bounds := AABB(-half, half * 2.0).grow(HAND_RADIUS)
	var hit = bounds.intersects_segment(inverse * from, inverse * to)
	if hit == null:
		return Vector3.ZERO
	# only push into the touched face so pulling away never drags the cube
	var normal := Vector3.ZERO
	var nearest := INF
	for axis in range(3):
		for side in [-1.0, 1.0]:
			var face: float = bounds.end[axis] if side > 0.0 else bounds.position[axis]
			var distance: float = absf(hit[axis] - face)
			if distance < nearest:
				nearest = distance
				normal = Vector3.ZERO
				normal[axis] = side
	normal = (inverse.basis.transposed() * normal).normalized()
	return -normal * maxf(0.0, -motion.dot(normal)) * PUSH_STRENGTH
