extends Control

const FONT := preload("res://IntroRust-Base.otf")
const FONT_SIZE := 64
const FONT_COLOR := Color(0.125, 0.58, 0.75) # make it blue

var text := "":
	set(value):
		text = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var font_size := FONT_SIZE
	while font_size > 12 and FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - 32.0:
		font_size -= 1
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2((size.x - width) * 0.5,
		(size.y - FONT.get_height(font_size)) * 0.5 + FONT.get_ascent(font_size))
	# a short red falloff keeps the glow close to the letters
	for radius in range(12, 0, -1):
		var opacity := 0.3 * exp(-float(radius) * 0.25)
		draw_string_outline(FONT, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, radius, Color(1.0, 0.025, 0.015, opacity))
	draw_string(FONT, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, FONT_COLOR)
