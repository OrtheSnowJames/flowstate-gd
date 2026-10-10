extends Node

var failed := false


func _ready() -> void:
	var had_override := OS.has_environment("FLOWSTATE_MATCHMAKING_URL")
	var old_override := OS.get_environment("FLOWSTATE_MATCHMAKING_URL")
	OS.unset_environment("FLOWSTATE_MATCHMAKING_URL")
	var expected := FileAccess.get_file_as_string(Matchmaking.URL_FILE).strip_edges().trim_suffix("/")
	_expect(not expected.is_empty(), "url file contains endpoint")
	_expect(Matchmaking._load_endpoint() == expected, "endpoint comes from text file")
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
