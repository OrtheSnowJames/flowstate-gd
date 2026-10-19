extends Node3D

const EYE_HEIGHT := 1.05

var pose: Array = []
var _display: Array = []
var _hands: Array[Node3D] = []
var _rig: Node3D
var _team := -1
var _hidden := false
var _original_arms: Array[Node3D] = []
var _body_layers: Dictionary = {}


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
	for i in range(2):
		var hand := Node3D.new()
		hand.name = "LeftHand" if i == 0 else "RightHand"
		add_child(hand)
		_hands.append(hand)
	hide()
	RenderingServer.frame_pre_draw.connect(_before_draw)
	_process(0.0)


func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(_before_draw)
	_restore_body_layers()


func _rebuild_arms() -> void:
	_original_arms.clear()
	for i in range(2):
		for child in _hands[i].get_children():
			_hands[i].remove_child(child)
			child.queue_free()
		if not _rig:
			continue
		var source := _rig.find_child("larm" if i == 0 else "rarm", true, false) as Node3D
		if not source:
			continue
		_original_arms.append(source)
		var arm := source.duplicate(0) as Node3D
		arm.name = "Arm"
		_hands[i].add_child(arm)
		arm.show()
		var bounds := AABB()
		var first := true
		for mesh in get_parent()._mesh_instances_in(source):
			var copy := arm.get_node(source.get_path_to(mesh)) as MeshInstance3D
			copy.layers = _body_layers.get(mesh, mesh.layers)
			copy.show()
			var box: AABB = (source.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		# center the model on the grip with the arm facing forward
		var basis := Basis(Vector3.RIGHT, -PI / 2.0).scaled(_rig.scale)
		arm.transform = Transform3D(basis, -(basis * bounds.get_center()))


func _before_draw() -> void:
	if get_parent()._is_local() and VR.immersive:
		_process(0.0)
	else:
		_sync_body_visibility()


func _sync_body_visibility() -> void:
	if get_parent()._is_local() and VR.immersive:
		_mask_body(get_parent())
		for geometry in _body_layers.keys():
			if not is_instance_valid(geometry):
				_body_layers.erase(geometry)
	else:
		_restore_body_layers()


func _mask_body(node: Node) -> void:
	if node == self:
		return
	if node is GeometryInstance3D:
		if not _body_layers.has(node):
			_body_layers[node] = node.layers
		# no camera can draw the local body even if an animation shows it
		node.layers = 0
	for child in node.get_children():
		_mask_body(child)


func _restore_body_layers() -> void:
	for geometry in _body_layers:
		if is_instance_valid(geometry):
			geometry.layers = _body_layers[geometry]
	_body_layers.clear()


func _process(delta: float) -> void:
	_sync_body_visibility()
	var player = get_parent()
	var local: bool = player._is_local()
	var shown := pose
	if local:
		pose = VR.body_pose(player)
		# local tracking is independent of network pose limits
		shown = VR.immersion.body_pose(player, false) if VR.immersive else []
	var rig: Node3D = player.get_node_or_null("blockbench_export")
	if rig != _rig or player.team != _team:
		_rig = rig
		_team = player.team
		_rebuild_arms()
	var enabled := not shown.is_empty()
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
		_display = shown.duplicate()
	else:
		for i in range(3):
			_display[i] = _display[i].interpolate_with(pose[i], 1.0 - exp(-25.0 * delta))
		_display[3] = pose[3]
	for i in range(2):
		var tracked: bool = (_display[3] & (1 << i)) != 0
		_hands[i].visible = tracked
		if not tracked:
			continue
		var wrist: Transform3D = _display[i + 1]
		_hands[i].transform = wrist
