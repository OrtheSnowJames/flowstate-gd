extends Control

var player: Node3D


func _process(_delta: float) -> void:
	var party := Net.pool_party()
	visible = is_instance_valid(player) and party != null and party.active() \
		and not player._unconscious and not Net.is_spectating() and not Net.input_blocked_by_menu()
	if not visible:
		return
	var count: int = party.carried(player).size()
	$Inventory.text = "Balloons: %d/%d" % [count, party.capacity(player)]
	var id: int = party.pickup_target(player) if Settings.show_movement_prompts else 0
	$Box.visible = id != 0
	if id == 0:
		return
	var item: Dictionary = party.items[id]
	var world: Vector3 = party.bucket.global_position if item.state == "bucket" else item.position
	world += Vector3.UP * 0.8
	var camera: Camera3D = VR.view_camera(player._camera)
	if camera == null or camera.is_position_behind(world):
		$Box.hide()
		return
	var key := "R"
	for event in InputMap.action_get_events("revive"):
		if event is InputEventKey:
			key = OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
			break
	$Box/Row/Keycap/Key.text = "Right Stick" if VR.active else ("Right D-pad" if player.using_controller else key)
	$Box/Row/Action.text = "Take balloon" if item.state == "bucket" else "Pick up balloon"
	$Box.reset_size()
	var screen := get_global_transform_with_canvas().affine_inverse() * VR.project_ui_position(world, camera)
	$Box.position = (screen - Vector2($Box.size.x * 0.5, $Box.size.y)).clamp(Vector2(8, 8), (size - $Box.size - Vector2(8, 8)).max(Vector2(8, 8)))
