extends Control

@onready var _label: Label = get_node("CenterContainer/Label")

# these two must add up to 1 second for the animation to work correctly
const _VISIBLE_TIME := 0.7
const _EXIT_TIME := 0.3
# how far the text spins on its way out in radians just past a
const _EXIT_ROTATION := PI * 0.6

# kill and recreate per call not a single onready tween same reasoning as other_scripts
var _tween: Tween


func _ready() -> void:
	modulate.a = 0.0


# shows text holds it for _visible_time then spins shrinks fades it away over _exit_time
func play(text: String) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = text
	_label.rotation = 0.0
	_label.scale = Vector2.ONE
	modulate.a = 1.0

	# one frame so the labels real size driven by the new text and its
	await get_tree().process_frame
	_label.pivot_offset = _label.size * 0.5

	# font_size 500 see the scenes labelsettings is sized for a single countdown digit or
	var available := size * 0.9
	var natural := _label.size
	var fit := 1.0
	if natural.x > 0.0 and natural.y > 0.0:
		fit = minf(1.0, minf(available.x / natural.x, available.y / natural.y))
	# applied as the tweens starting scale not a separate step the shrink and the
	_label.scale = Vector2.ONE * fit

	_tween = create_tween()
	_tween.tween_interval(_VISIBLE_TIME)
	_tween.tween_property(_label, "rotation", _EXIT_ROTATION, _EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_label, "scale", Vector2.ZERO, _EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, _EXIT_TIME)
	await _tween.finished
