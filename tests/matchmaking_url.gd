extends Node

var failed := false


func _ready() -> void:
	var had_override := OS.has_environment("FLOWSTATE_MATCHMAKING_URL")
	var old_override := OS.get_environment("FLOWSTATE_MATCHMAKING_URL")
	OS.unset_environment("FLOWSTATE_MATCHMAKING_URL")
	var expected := FileAccess.get_file_as_string(Matchmaking.URL_FILE).strip_edges().trim_suffix("/")
	_expect(not expected.is_empty(), "url file contains endpoint")
	_expect(Matchmaking._load_endpoint() == expected, "endpoint comes from text file")
	var presets := ConfigFile.new()
	_expect(presets.load("res://export_presets.cfg") == OK, "export presets load")
	for section in presets.get_sections():
		if presets.has_section_key(section, "platform"):
			var includes: String = presets.get_value(section, "include_filter", "")
			_expect(includes.split(",").has("connect_to_url.txt"), "%s packages the matchmaking url" % presets.get_value(section, "name"))
	var was_quest: bool = VR.quest_standalone
	var old_endpoint: String = Matchmaking.endpoint
	VR.quest_standalone = true
	Matchmaking.endpoint = Matchmaking._load_endpoint()
	_expect(Matchmaking.configured(), "standalone quest can use matchmaking")
	_expect(Net.host_game() == ERR_UNAVAILABLE, "standalone quest still cannot host")
	_expect(not Net.is_online(), "rejected hosting leaves networking offline")
	VR.quest_standalone = was_quest
	Matchmaking.endpoint = old_endpoint
	OS.set_environment("FLOWSTATE_MATCHMAKING_URL", "  http://127.0.0.1:18765/\n")
	_expect(Matchmaking._load_endpoint() == "http://127.0.0.1:18765", "local override takes priority and is trimmed")
	OS.set_environment("FLOWSTATE_MATCHMAKING_URL", " \n")
	_expect(Matchmaking._load_endpoint() == expected, "blank override falls back to text file")
	if had_override:
		OS.set_environment("FLOWSTATE_MATCHMAKING_URL", old_override)
	else:
		OS.unset_environment("FLOWSTATE_MATCHMAKING_URL")
	print("FAIL matchmaking url" if failed else "PASS matchmaking url")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
