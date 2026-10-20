extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected the staged project directory")
		quit(1)
		return
	var path := args[0].path_join("project.godot")
	var project := ConfigFile.new()
	var overrides := ConfigFile.new()
	if project.load(path) != OK or overrides.load(args[0].path_join("quest_import.cfg")) != OK:
		push_error("Could not load the staged project or Quest import settings")
		quit(1)
		return
	# editor imports ignore runtime override files
	for section in overrides.get_sections():
		for key in overrides.get_section_keys(section):
			project.set_value(section, key, overrides.get_value(section, key))
	var result := project.save(path)
	if result != OK:
		push_error("Could not save staged Quest settings: " + error_string(result))
	else:
		print("Quest import settings applied to staged project")
	quit(0 if result == OK else 1)
