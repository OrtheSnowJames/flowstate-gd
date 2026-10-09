extends MultiMeshInstance3D

# replaces the 32 individual pine tscn instances that used to live under staticbody3d2 trees

const _TREE_SCENE := preload("res://pine.tscn")

# the 16 local offsets shared by both original groups copied verbatim from ocean1 tscns
const _LOCAL_OFFSETS := [
	Vector3(-42.72, 9, -40.37),
	Vector3(-39.45, 9, -39.38),
	Vector3(-34.53, 9, -37.12),
	Vector3(-30.22, 9, -40.07),
	Vector3(-27.16, 9, -40.35),
	Vector3(-23.56, 9, -37.97),
	Vector3(-19.95, 9, -39.51),
	Vector3(-14.7, 9, -37.78),
	Vector3(-11.56, 9, -37.55),
	Vector3(-6.38, 9, -40.47),
	Vector3(-2.39, 9, -37.01),
	Vector3(0.68, 9, -39.72),
	Vector3(5.91, 9, -38.82),
	Vector3(8.19, 9, -40.02),
	Vector3(13.69, 9, -37.48),
	Vector3(17.61, 9, -36.85),
]

# the two original group trees trees2 transforms copied verbatim from ocean1 tscn this node
const _GROUP_TRANSFORMS := [
	Transform3D(Vector3(-4.371139e-08, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, -4.371139e-08),
		Vector3(-40, -9, 36)),
	Transform3D(Vector3(-4.8082526e-08, 0, -1), Vector3(0, 1, 0), Vector3(1.1, 0, -4.371139e-08),
		Vector3(-35, -9, 38)),
]


func _ready() -> void:
	var mesh := _find_mesh(_TREE_SCENE)
	if mesh == null:
		push_warning("tree_multimesh: couldn't find a mesh inside pine.tscn -- no trees to draw")
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _GROUP_TRANSFORMS.size() * _LOCAL_OFFSETS.size()

	var i := 0
	for group_xform in _GROUP_TRANSFORMS:
		for offset in _LOCAL_OFFSETS:
			mm.set_instance_transform(i, group_xform * Transform3D(Basis.IDENTITY, offset))
			i += 1
	multimesh = mm


# instantiates scene just long enough to walk it for the first meshinstance3ds mesh then
func _find_mesh(scene: PackedScene) -> Mesh:
	var temp := scene.instantiate()
	var mesh := _find_mesh_in(temp)
	temp.queue_free()
	return mesh


func _find_mesh_in(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh != null:
		return node.mesh
	for child in node.get_children():
		var found := _find_mesh_in(child)
		if found != null:
			return found
	return null
