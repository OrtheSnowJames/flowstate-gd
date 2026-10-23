extends Control

@onready var _label: Label = $Label

# these two must add up to 1 second for the animation to work correctly
const _VISIBLE_TIME := 0.7
const _EXIT_TIME := 0.3
# rotation at the end of the exit animation
const _EXIT_ROTATION := PI * 0.6

# kill and recreate per call not a single onready tween same reasoning as other_scripts
var _tween: Tween
var _exit_progress := 0.0


func _ready() -> void:
	modulate.a = 0.0
	resized.connect(_layout_message)


# shows text holds it for _visible_time then spins shrinks fades it away over _exit_time
func play(text: String) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = text
	_exit_progress = 0.0
	_layout_message()
	modulate.a = 1.0

	_tween = create_tween()
	_tween.tween_interval(_VISIBLE_TIME)
	_tween.tween_method(_animate_exit, 0.0, 1.0, _EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, _EXIT_TIME)
	await _tween.finished


func _animate_exit(progress: float) -> void:
	_exit_progress = progress
	_layout_message()


func _layout_message() -> void:
	var natural := _label.get_combined_minimum_size()
	_label.size = natural
	_label.position = (size - natural) * 0.5
	_label.pivot_offset = natural * 0.5
	_label.rotation = _EXIT_ROTATION * _exit_progress
	var available := size * 0.85
	var fit := minf(1.0, minf(available.x / maxf(natural.x, 1.0), available.y / maxf(natural.y, 1.0)))
	# keep the rotated bounds inside the same margins while shrinking
	var cosine := absf(cos(_label.rotation))
	var sine := absf(sin(_label.rotation))
	var bounds := Vector2(natural.x * cosine + natural.y * sine, natural.x * sine + natural.y * cosine)
	fit = minf(fit * (1.0 - _exit_progress), minf(available.x / maxf(bounds.x, 1.0), available.y / maxf(bounds.y, 1.0)))
	_label.scale = Vector2.ONE * maxf(fit, 0.0)
