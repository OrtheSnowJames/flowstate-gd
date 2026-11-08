extends AudioStreamPlayer

const TITLE = preload("res://audio/title-evansong1.mp3")
const NORMAL = preload("res://audio/normal-kotc-evansong2.mp3")
const ARCADE = preload("res://audio/arcade-fpp-evansong3.mp3")
const SOLO = preload("res://audio/solo-evansong4.mp3")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bus = &"Music"
	volume_db = -12.0
	for track in [TITLE, NORMAL, ARCADE, SOLO]:
		track.loop = true
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(_update_track)
	add_child(timer)
	timer.start()
	_update_track.call_deferred()


func _update_track() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var next_track: AudioStream = TITLE
	if scene.scene_file_path == "res://water/ocean1.tscn":
		if not Net.is_online() or Net.couch_practice:
			next_track = SOLO
		elif Net.game_mode in [Net.GameMode.ARCADE, Net.GameMode.POOL_PARTY]:
			next_track = ARCADE
		else:
			next_track = NORMAL
	if stream != next_track:
		stream = next_track
		play()
