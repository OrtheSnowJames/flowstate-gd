extends SceneTree


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var paths: Array[String] = ["res://menu/menu.tscn", "res://water/ocean1.tscn", "res://water/vr_room.tscn"]
	for file in DirAccess.get_files_at("res://mesh"):
		if file.get_extension().to_lower() in ["glb", "gltf", "fbx", "obj", "png", "jpg", "jpeg", "tscn"]:
			paths.append("res://mesh/" + file)
	var failed := false
	for path in paths:
		if ResourceLoader.load(path) == null:
			push_error("Resource validation failed: " + path)
			failed = true
	print("FAIL resource validation" if failed else "PASS resource validation")
	quit(1 if failed else 0)
