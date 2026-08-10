extends SceneTree

var _frames := 0


func _initialize() -> void:
	root.add_child(load("res://water/ocean1.tscn").instantiate())


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames != 20:
		return _frames >= 30

	var player: RigidBody3D = root.get_node("Main/our_player")
	var water: Area3D = root.get_node("Main/water base")

	# --- how big is the visible player, really -------------------------------
	var model: Node3D = player.get_node("blockbench_export")
	var box := AABB()
	var first := true
	for mi in _all_meshes(model):
		var a: AABB = mi.get_aabb()
		# into player-local space
		var t: Transform3D = player.global_transform.affine_inverse() * mi.global_transform
		var local := t * a
		box = local if first else box.merge(local)
		first = false
	print("MODEL  visible height=%.2f m  width=%.2f m  y from %.2f to %.2f" % [
			box.size.y, box.size.x, box.position.y, box.position.y + box.size.y])
	print("MODEL  node scale=", model.scale, "  y offset=%.2f" % model.position.y)
	var cap: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	print("BODY   collision capsule height=%.2f m  radius=%.2f m" % [cap.height, cap.radius])
	print("BODY   floats with %.2f m clear of the water (target_submersion=%.2f)" % [
			player.body_half_height * (1.0 - 2.0 * player.target_submersion)
					+ player.body_half_height,
			player.target_submersion])

	# --- how tall is the swim wake -------------------------------------------
	print("\nWAKE   sim clamps displacement to +/-0.5, shown at amplitude=%.2f" % water.amplitude)
	print("       so the tallest possible wave is %.2f m\n" % (0.5 * water.amplitude))
	var mass_f: float = clampf(sqrt(player.body_mass / water.default_mass), 0.35, 2.5)
	print("       per-tick crest injected while swimming (60 Hz, full speed):")
	for ws in [4.0, 2.0, 1.0, 0.7, 0.4]:
		var push: float = ws * mass_f * 1.0 * (1.0 / 60.0) * 7.0
		var note := "  <-- SATURATES the clamp in 2 ticks" if push > 0.24 else ""
		print("         wake_strength %4.1f -> %.3f m/tick (%.0f%% of clamp)%s" % [
				ws, push, push / 0.5 * 100.0, note])
	return true


func _all_meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
