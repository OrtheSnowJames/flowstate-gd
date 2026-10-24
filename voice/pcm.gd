extends RefCounted

const RATE := 16000
const FRAMES := 320
const BYTES := FRAMES * 2


static func encode(input: PackedVector2Array) -> PackedByteArray:
	var packet := PackedByteArray()
	if input.is_empty():
		return packet
	packet.resize(BYTES)
	var step := float(input.size()) / FRAMES
	for i in FRAMES:
		var offset := i * step
		var index := int(offset)
		var frame := input[index].lerp(input[mini(index + 1, input.size() - 1)], offset - index)
		var sample := clampf((frame.x + frame.y) * 0.5, -1.0, 1.0)
		packet.encode_s16(i * 2, roundi(sample * 32767.0))
	return packet


static func decode(packet: PackedByteArray) -> PackedVector2Array:
	var frames := PackedVector2Array()
	if packet.size() != BYTES:
		return frames
	frames.resize(FRAMES)
	for i in FRAMES:
		frames[i] = Vector2.ONE * (packet.decode_s16(i * 2) / 32768.0)
	return frames
