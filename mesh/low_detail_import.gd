@tool
extends EditorScenePostImport


func _post_import(scene: Node) -> Object:
	_reduce_nodes(scene, {})
	return scene


func _reduce_nodes(node: Node, meshes: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh is ArrayMesh and node.skin == null:
		var original: ArrayMesh = node.mesh
		if not meshes.has(original):
			meshes[original] = _reduce_mesh(original)
		node.mesh = meshes[original]
	for child in node.get_children():
		_reduce_nodes(child, meshes)


func _reduce_mesh(original: ArrayMesh) -> ArrayMesh:
	if original.get_blend_shape_count() > 0:
		return original
	var source := ImporterMesh.from_mesh(original)
	var reduced := ImporterMesh.new()
	var changed := false
	for surface in range(source.get_surface_count()):
		var arrays := source.get_surface_arrays(surface)
		var first_lod := 0
		if source.get_surface_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES and source.get_surface_lod_count(surface) > 0:
			var indices := source.get_surface_lod_indices(surface, 0)
			# keep tiny details intact and use the first lower detail level elsewhere
			if indices.size() >= 96:
				arrays[Mesh.ARRAY_INDEX] = indices
				first_lod = 1
				changed = true
		var lods := {}
		for lod in range(first_lod, source.get_surface_lod_count(surface)):
			lods[source.get_surface_lod_size(surface, lod)] = source.get_surface_lod_indices(surface, lod)
		reduced.add_surface(source.get_surface_primitive_type(surface), arrays, [], lods,
			source.get_surface_material(surface), source.get_surface_name(surface), source.get_surface_format(surface))
	if not changed:
		return original
	# reuse generated lods so lowering detail does not run the simplifier again
	reduced.set_lightmap_size_hint(source.get_lightmap_size_hint())
	var result := reduced.get_mesh()
	result.resource_name = original.resource_name
	result.custom_aabb = original.custom_aabb
	result.shadow_mesh = original.shadow_mesh
	return result
