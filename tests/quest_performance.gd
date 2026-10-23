extends Node

const CODE := preload("res://vr/quest_test_code.gd")
var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var code := CODE.new()
	_expect(_sequence(code), "complete code accepted")
	_expect(not code.update(false, false, 1.0, 0.0, 0.1), "held final direction does not repeat")
	code.reset()
	code.update(true, false, 0.0, 0.0, 0.1)
	for i in range(10):
		code.update(true, false, 0.0, 0.0, 0.1)
	_expect(code._step == 1, "holding a counts once")
	code.update(false, true, 0.0, 0.0, 0.1)
	_expect(code._step == 0, "wrong order resets")
	code.update(false, false, 0.0, 0.0, 0.1)
	code.update(true, false, 0.0, 0.0, 0.1)
	code.update(false, false, 0.0, 0.0, 3.1)
	_expect(code._step == 0, "idle timeout resets")
	code.update(true, true, 0.0, 0.0, 0.1)
	_expect(code._step == 0, "simultaneous buttons rejected")
	code.reset()
	_expect(_sequence(code, true), "right stick also accepted")
	code.reset()
	for button in ["a", "a", "b", "b"]:
		code.update(button == "a", button == "b", 0.0, 0.0, 0.1)
		code.update(false, false, 0.0, 0.0, 0.1)
	code.update(false, false, -0.8, 0.0, 0.1)
	code.update(false, false, -0.5, 0.0, 0.1)
	code.update(false, false, -0.8, 0.0, 0.1)
	_expect(code._step == 5, "stick jitter counts once")

	var saved: bool = Settings._performance_mode
	var saved_fps := Engine.max_fps
	VR.active = true
	VR.quest_standalone = true
	Settings.performance_mode = true
	VR._apply_quest_fps_limit()
	_expect(Engine.max_fps == 60, "quest starts capped at 60 fps")
	var pool := Node3D.new()
	pool.set_script(load("res://water/pool_scene_toggles.gd"))
	pool.water_path = ^"Water"
	var water := FluidBox.new()
	water.name = "Water"
	pool.add_child(water)
	add_child(pool)
	var collision := water.get_child(0)
	_expect(Settings.performance_mode and water._sim_size.x == 192, "quest starts in performance mode")
	_vr_sequence()
	await get_tree().process_frame
	_expect(not Settings.performance_mode, "code disables forced quest performance even with saved preference on")
	_expect(Engine.max_fps == 40, "quest quality mode caps at 40 fps")
	_expect(water._sim_size.x == 384 and water._mesh.mesh.subdivide_width == 300, "quality rebuilds live water")
	_expect(not water._surf_mat.get_shader_parameter("simple_surface"), "quality shader updates live")
	_expect(water.get_child(0) == collision, "water collision preserved")
	_vr_sequence()
	await get_tree().process_frame
	_expect(Settings.performance_mode and water._sim_size.x == 192, "repeating code restores performance")
	_expect(Engine.max_fps == 60, "quest performance mode restores 60 fps cap")
	VR.immersive = true
	_vr_sequence()
	_expect(Settings.performance_mode, "immersive mode ignores code")
	VR.immersive = false
	VR.entering = true
	_vr_sequence()
	_expect(Settings.performance_mode, "transition ignores code")
	VR.entering = false
	VR.quest_standalone = false
	_vr_sequence()
	_expect(Settings.performance_mode, "pcvr ignores code")
	VR.quest_standalone = true
	_vr_sequence()
	VR.stop()
	_expect(Settings.performance_mode, "stopping vr resets override")
	_expect(Engine.max_fps == 60, "resetting quest quality restores 60 fps cap")
	_expect(Settings._performance_mode, "hidden code never modifies saved preference")
	VR.quest_standalone = false
	Engine.max_fps = 77
	Settings.performance_mode = false
	_expect(not Settings.performance_mode, "desktop setting still works")
	_expect(Engine.max_fps == 77, "desktop frame cap stays unchanged")
	pool.queue_free()
	await get_tree().process_frame
	Settings._performance_mode = saved
	Engine.max_fps = saved_fps
	var desktop := ConfigFile.new()
	desktop.load("res://project.godot")
	_expect(desktop.get_value("rendering", "textures/vram_compression/import_etc2_astc"), "editor imports textures for native quest exports")
	_expect(desktop.get_value("rendering", "renderer/rendering_method.mobile") == "gl_compatibility", "native quest export uses compatibility")
	_expect(desktop.get_value("xr", "openxr/enabled.android"), "native quest export enables openxr")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var found := false
	for section in presets.get_sections():
		if presets.get_value(section, "name", "") != "Meta Quest":
			continue
		found = true
		_expect("connect_to_url.txt" in presets.get_value(section, "include_filter", ""), "native quest export includes matchmaking configuration")
		for key in ["gradle_build/use_gradle_build", "xr_features/enable_meta_plugin", "meta_xr_features/use_overlay_keyboard", "permissions/internet"]:
			_expect(presets.get_value(section + ".options", key, false), "native quest export enables " + key)
	_expect(found, "quest export preset exists")
	var quest := ConfigFile.new()
	quest.load("res://quest_import.cfg")
	_expect(quest.get_value("rendering", "textures/vram_compression/import_etc2_astc"), "quest enables mobile imports")
	print("FAIL quest performance" if failed else "PASS quest performance")
	get_tree().quit(1 if failed else 0)


func _sequence(code, right_stick := false) -> bool:
	var completed := false
	for token in CODE.SEQUENCE:
		var x := -1.0 if token == "left" else (1.0 if token == "right" else 0.0)
		completed = code.update(token == "a", token == "b", 0.0 if right_stick else x,
			x if right_stick else 0.0, 0.1)
		code.update(false, false, 0.0, 0.0, 0.1)
	return completed


func _vr_sequence() -> void:
	for token in CODE.SEQUENCE:
		var x := -1.0 if token == "left" else (1.0 if token == "right" else 0.0)
		VR._update_quest_test_code(token == "a", token == "b", x, 0.0, 0.1)
		VR._update_quest_test_code(false, false, 0.0, 0.0, 0.1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
