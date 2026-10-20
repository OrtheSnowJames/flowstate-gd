extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(get_viewport().get_camera_3d() == get_parent().get_node("Camera3D"))
	assert(VR.start(true))
	VR.quest_standalone = true
	VR.enter_immersive()
	await get_tree().create_timer(1.0).timeout
	assert(VR.immersive)
	assert(VR.immersion.blur.material_override.shader == load("res://vr/menu_dim.gdshader"))
	assert(VR.room_view.find_world_3d() == get_tree().root.find_world_3d())
	assert(VR.immersion.blur.visible)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.0).timeout
		RenderingServer.force_draw()
		var picture := VR.room_view.get_texture().get_image()
		picture.save_png("/tmp/flowstate-quest-menu.png")
		var lit := 0
		for y in range(0, picture.get_height(), 24):
			for x in range(0, picture.get_width(), 24):
				if picture.get_pixel(x, y).get_luminance() > 0.05:
					lit += 1
		assert(lit > 300, "quest menu background is visible through dim layer")
	VR.stop()
	VR.quest_standalone = false
	assert(not get_tree().root.disable_3d)
	print("PASS quest menu background")
	get_tree().quit()
