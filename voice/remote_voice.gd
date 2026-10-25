extends AudioStreamPlayer

const PCM := preload("res://voice/pcm.gd")
const MAX_PACKETS := 8

var packets := {}
var next_sequence := -1
var last_received := 0
var first_received := 0
var missing_since := 0
var playback: AudioStreamGeneratorPlayback
var capacity := 0
var _gain := 1.0
var _has_gain := false
var speaking_until := 0
var _spatial: AudioStreamPlayer3D


func spatial_at(parent: Node3D) -> void:
	_spatial = AudioStreamPlayer3D.new()
	_spatial.stream = stream
	_spatial.unit_size = 2.0
	_spatial.max_distance = 12.0
	parent.add_child(_spatial)


func output() -> Node:
	return _spatial if is_instance_valid(_spatial) else self


func _exit_tree() -> void:
	if is_instance_valid(_spatial):
		_spatial.queue_free()


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = PCM.RATE
	generator.buffer_length = 0.16
	stream = generator
	volume_db = 0.0


func receive(sequence: int, data: PackedByteArray) -> void:
	if sequence < next_sequence or packets.has(sequence):
		return
	var now := Time.get_ticks_msec()
	if next_sequence < 0:
		next_sequence = sequence
		first_received = now
	last_received = now
	var frames := _normalize(PCM.decode(data))
	packets[sequence] = frames
	# discard stale audio instead of letting latency grow
	if packets.size() > MAX_PACKETS:
		output().stop()
		playback = null
		packets = {sequence: frames}
		next_sequence = sequence
		first_received = now
		missing_since = 0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if last_received > 0 and now - last_received > 750:
		queue_free()
		return
	if packets.is_empty():
		return
	if playback == null:
		if packets.size() < 3 and now - first_received < 60:
			return
		output().play()
		playback = output().get_stream_playback()
		capacity = playback.get_frames_available()
	while not packets.is_empty() and capacity - playback.get_frames_available() < PCM.FRAMES * 3:
		if not playback.can_push_buffer(PCM.FRAMES):
			break
		if not packets.has(next_sequence):
			if missing_since == 0:
				missing_since = now
			if now - missing_since < 20:
				break
			var earliest: int = packets.keys().min()
			# one silent frame conceals loss without replaying a long gap
			var silence := PackedVector2Array()
			silence.resize(PCM.FRAMES)
			playback.push_buffer(silence)
			next_sequence = earliest
			missing_since = 0
			continue
		playback.push_buffer(packets[next_sequence])
		packets.erase(next_sequence)
		next_sequence += 1
		missing_since = 0


func _normalize(frames: PackedVector2Array) -> PackedVector2Array:
	var energy := 0.0
	var peak := 0.0
	for frame in frames:
		energy += frame.x * frame.x
		peak = maxf(peak, absf(frame.x))
	var rms := sqrt(energy / maxi(1, frames.size()))
	if rms >= 0.002:
		speaking_until = Time.get_ticks_msec() + 300
		var desired := clampf(0.16 / rms, 1.0, 16.0)
		# boost quiet voices gradually and limit peaks immediately
		_gain = lerpf(_gain, desired, 0.12 if desired > _gain else 0.8) if _has_gain else desired
		_has_gain = true
	if peak > 0.0:
		_gain = minf(_gain, 0.9 / peak)
	for i in frames.size():
		frames[i] *= _gain
	return frames
