extends Node3D

const RIG := preload("res://mesh/character.glb")
const APPEARANCE := preload("res://water/player/appearance.gd")
const ARMS := preload("res://water/player/vr_arms.gd")
static var _materials: Dictionary = {}
var body: Node3D
var hands: Array[Node3D] = []
var local := false
var team := -2
var target: Array = []
var shown: Array = []
var voice_origin: Node3D
var _head: Node3D
var _head_rest: Transform3D


func _ready() -> void:
	body = RIG.instantiate()
	add_child(body)
	body.scale = Vector3.ONE * 0.5
	body.position.y = -2.1
	_head = body.find_child("head", true, false)
	_head_rest = _head.transform
	voice_origin = Node3D.new()
	add_child(voice_origin)
	for limb in ["rleg", "rleg2"]:
		var leg := body.find_child(limb, true, false) as Node3D
		if leg:
			var bounds := AABB()
			var first := true
			for mesh in meshes(leg):
				var box: AABB = (leg.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
				bounds = box if first else bounds.merge(box)
				first = false
			# bend from the hip rather than the imported animation pivot
			var pivot := bounds.get_center()
			pivot.y = bounds.end.y
			var bend := Basis(Vector3.RIGHT, PI / 3.0)
			leg.transform = leg.transform * Transform3D(bend, pivot - bend * pivot)
	for side in ["larm", "rarm"]:
		var source := body.find_child(side, true, false) as Node3D
		var hand := Node3D.new()
		add_child(hand)
		hands.append(hand)
		hand.hide()
		if not source:
			continue
		var arm := source.duplicate(0) as Node3D
		hand.add_child(arm)
		var bounds := AABB()
		var first := true
		for mesh in meshes(source):
			var box: AABB = (source.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		var basis := Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3.ONE * 0.5)
		var tip := bounds.get_center()
		tip.y = bounds.end.y
		arm.transform = Transform3D(basis, -(basis * tip))
		source.hide()


func meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(meshes(child))
	return result


func setup(seat: Transform3D, color_team: int, is_local: bool) -> void:
	global_transform = seat
	local = is_local
	body.visible = not local
	if team == color_team:
		return
	team = color_team
	var color := Color.WHITE if team < 0 else (Color("d92d2d") if team == 0 else Color("2d6bd9"))
	for mesh in meshes(self):
		for surface in mesh.mesh.get_surface_count():
			var base = mesh.mesh.surface_get_material(surface)
			if base is StandardMaterial3D and base.albedo_texture:
				var key := [base.get_rid(), team]
				if not _materials.has(key):
					var material: StandardMaterial3D = base.duplicate()
					material.albedo_texture = APPEARANCE._tinted_texture(base.albedo_texture, color)
					_materials[key] = material
				mesh.set_surface_override_material(surface, _materials[key])


func apply_pose(pose: Array, interval: float) -> void:
	target = pose.duplicate()
	if local or shown.is_empty() or interval <= 0.0:
		shown = target.duplicate()
		_process(0.0)


func _process(delta: float) -> void:
	if target.is_empty():
		for hand in hands:
			hand.hide()
		return
	if not local:
		for i in range(3):
			shown[i] = shown[i].interpolate_with(target[i], 1.0 - exp(-25.0 * delta))
	voice_origin.transform = shown[0]
	_head.transform = Transform3D(shown[0].basis, _head_rest.origin + shown[0].origin * 2.0)
	for i in range(2):
		hands[i].visible = (target[3] & (1 << i)) != 0
		var wrist: Transform3D = shown[i + 1]
		if not local:
			wrist.origin += ARMS.REMOTE_ARM_OFFSET
		hands[i].transform = wrist
