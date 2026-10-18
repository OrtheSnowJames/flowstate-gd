extends Node3D

const EYE_HEIGHT := 1.05
const ARM_DROP := EYE_HEIGHT * 0.5

var pose: Array = []
var _display: Array = []
var _segments: Array[MeshInstance3D] = []
var _hands: Array[MeshInstance3D] = []
var _rig: Node3D
var _hidden := false
var _original_arms: Array[Node3D] = []


static func valid_pose(value: Array) -> bool:
	if value.is_empty():
		return true
	if value.size() != 4 or not value[3] is int or value[3] < 0 or value[3] > 3:
		return false
	for i in range(3):
		if not value[i] is Transform3D:
			return false
		var transform: Transform3D = value[i]
		if not transform.is_finite() or transform.origin.length() > 3.0:
			return false
		if not transform.basis.is_equal_approx(transform.basis.orthonormalized()):
			return false
		if i > 0 and transform.origin.distance_to(value[0].origin) > 1.8:
			return false
	return true


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.57, 0.43)
	material.roughness = 0.85
	for i in range(4):
		var segment := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.055
		mesh.bottom_radius = 0.075
		mesh.height = 1.0
		mesh.radial_segments = 8
		segment.mesh = mesh
		segment.material_override = material
		add_child(segment)
		_segments.append(segment)
	for i in range(2):
		var hand := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.13, 0.08, 0.18)
		hand.mesh = mesh
		hand.material_override = material
		add_child(hand)
		_hands.append(hand)
	hide()
	_process(0.0)


func _process(delta: float) -> void:
	var player = get_parent()
	var local: bool = player._is_local()
	if local:
		pose = VR.body_pose(player)
	var rig: Node3D = player.get_node_or_null("blockbench_export")
	if rig != _rig:
		_rig = rig
		_original_arms.clear()
		if rig:
			for arm_name in ["larm", "rarm"]:
				var arm := rig.find_child(arm_name, true, false) as Node3D
				if arm:
					_original_arms.append(arm)
	var enabled := not pose.is_empty()
	visible = enabled
	if _rig:
		if local and VR.immersive:
			_rig.hide()
			_hidden = true
		elif _hidden:
			_rig.show()
			_hidden = false
	for arm in _original_arms:
		arm.visible = not enabled
	if not enabled:
		_display.clear()
		return
	if local or _display.is_empty():
		_display = pose.duplicate()
	else:
		for i in range(3):
			_display[i] = _display[i].interpolate_with(pose[i], 1.0 - exp(-25.0 * delta))
		_display[3] = pose[3]
	var head: Transform3D = _display[0]
	var yaw := Basis(Vector3.UP, head.basis.get_euler().y)
	for i in range(2):
		var tracked: bool = (_display[3] & (1 << i)) != 0
		_hands[i].visible = tracked
		_segments[i * 2].visible = tracked
		_segments[i * 2 + 1].visible = tracked
		if not tracked:
			continue
		var side := -1.0 if i == 0 else 1.0
		var wrist: Transform3D = _display[i + 1]
		var shoulder := head.origin + yaw * Vector3(side * 0.22, -ARM_DROP, 0.04)
		var elbow := shoulder.lerp(wrist.origin, 0.5) + yaw * Vector3(side * 0.12, -0.18, 0.06)
		_segment(_segments[i * 2], shoulder, elbow)
		_segment(_segments[i * 2 + 1], elbow, wrist.origin)
		_hands[i].transform = wrist


func _segment(mesh: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var direction := end - start
	var length := maxf(direction.length(), 0.001)
	mesh.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction / length)), (start + end) * 0.5)
	mesh.scale.y = length
