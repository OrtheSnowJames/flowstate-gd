extends Node

const HandPush := preload("res://vr/hand_push.gd")
var failed := false


func _ready() -> void:
	var cube := preload("res://water/synced_prop.gd").new()
	cube.mass = 12.0
	cube.gravity_scale = 0.0
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3.ONE * 1.6
	cube.add_child(shape)
	add_child(cube)
	var push := HandPush.new()
	var from := Vector3(-1.05, 0, 0)
	var to := Vector3(-0.75, 0, 0)
	_expect(HandPush.contact_impulse(cube, from, to).x > 0.0, "touching a face pushes inward")
	_expect(HandPush.contact_impulse(cube, to, from).is_zero_approx(), "pulling away does not drag")
	_expect(HandPush.contact_impulse(cube, from, from).is_zero_approx(), "still hands do not push")
	_expect(HandPush.contact_impulse(cube, from + Vector3.UP * 2, to + Vector3.UP * 2).is_zero_approx(), "missing the cube does not push")
	_expect(HandPush.contact_impulse(cube, from * 10, to).is_zero_approx(), "tracking jumps do not launch the cube")
	cube.rotation.y = PI / 2.0
	_expect(HandPush.contact_impulse(cube, cube.to_global(from), cube.to_global(to)).z < 0.0, "rotated faces push in world space")
	cube.rotation = Vector3.ZERO
	_expect(not push.sample(cube, 0, from, true), "first tracking sample does not push")
	push.sample(cube, 0, from, false)
	_expect(not push.sample(cube, 0, to, true), "tracking recovery does not push")
	push.reset()
	_expect(not push.sample(cube, 1, to, true), "reset clears both hand histories")
	push.reset()
	await get_tree().physics_frame
	await get_tree().physics_frame
	push.sample(cube, 0, from, true)
	_expect(push.sample(cube, 0, to, true), "moving hand applies a contact impulse")
	await get_tree().create_timer(0.2).timeout
	_expect(cube.position.x > 0.1, "hand contact moves the solo physics cube")
	print("FAIL vr hand push" if failed else "PASS vr hand push")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
