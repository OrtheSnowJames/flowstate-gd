extends SceneTree

const PROPS := {
	"banana.glb": [1824, 1], "chairs.fbx": [1341, 4], "drone.fbx": [241144, 24],
	"playground.glb": [34960, 109], "stylized_pine.glb": [1396, 1], "toilet.glb": [10492, 5]
}
const PROTECTED := {"character.glb": 492, "lifeguard.glb": 612, "Gamegear.FBX": 5256, "Couch_01_.obj": 34044}
var failed := false


func _initialize() -> void:
	for file in PROPS:
		var stats := _inspect(file, true)
		_expect(stats.triangles > 0 and stats.triangles <= PROPS[file][0] * 0.6, file + " has lower detail geometry")
		_expect(stats.surfaces == PROPS[file][1], file + " retains all material surfaces")
	for file in PROTECTED:
		var stats := _inspect(file, false)
		_expect(stats.triangles == PROTECTED[file], file + " keeps its original geometry")
	print("FAIL model quality" if failed else "PASS model quality")
	quit(1 if failed else 0)


func _inspect(file: String, reduced: bool) -> Dictionary:
	var resource = load("res://mesh/" + file)
	var stats := {"triangles": 0, "surfaces": 0}
	if resource is PackedScene:
		var scene = resource.instantiate()
		_scan(scene, stats, reduced)
		scene.free()
	elif resource is Mesh:
		_mesh(resource, stats, reduced)
	return stats


func _scan(node: Node, stats: Dictionary, reduced: bool) -> void:
	if node is MeshInstance3D and node.mesh:
		_mesh(node.mesh, stats, reduced)
	for child in node.get_children():
		_scan(child, stats, reduced)


func _mesh(mesh: Mesh, stats: Dictionary, reduced: bool) -> void:
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var count: int = indices.size() if indices != null and not indices.is_empty() else vertices.size()
		stats.triangles += count / 3
		stats.surfaces += 1
		if indices != null and not indices.is_empty():
			var index_array := Array(indices)
			_expect(index_array.min() >= 0 and index_array.max() < vertices.size(), "mesh indices remain valid")
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		if material and reduced:
			for slot in range(BaseMaterial3D.TEXTURE_MAX):
				var texture := material.get_texture(slot)
				if texture:
					_expect(maxi(texture.get_width(), texture.get_height()) <= 512, texture.resource_path + " stays within 512 pixels")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
