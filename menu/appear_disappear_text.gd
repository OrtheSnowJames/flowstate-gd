extends Control

@onready var _label: Label = get_node("CenterContainer/Label")

# These two must add up to 1 second for the animation to work correctly.
const _VISIBLE_TIME := 0.7
const _EXIT_TIME := 0.3
## How far the text spins on its way out, in radians. Just past a quarter
## turn reads as a decisive flourish without going far enough to look like
## it's spinning in place.
const _EXIT_ROTATION := PI * 0.6

# Kill-and-recreate per call, not a single @onready Tween -- same reasoning
# as other_scripts/button_size_changer.gd: a Tween is single-use, so a second
# play() call needs a fresh one rather than trying to reuse a finished one.
var _tween: Tween


func _ready() -> void:
	modulate.a = 0.0


## Shows `text`, holds it for _VISIBLE_TIME, then spins/shrinks/fades it away
## over _EXIT_TIME. Awaitable -- resolves once it's fully gone.
##
## Safe to call again before a previous call has finished: the in-flight
## tween is killed and every animated property is reset to its resting state
## up front, so the new call starts clean instead of continuing a shrink or
## spin that was already partway through.
func play(text: String) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = text
	_label.rotation = 0.0
	_label.scale = Vector2.ONE
	modulate.a = 1.0

	# One frame so the label's real size -- driven by the new text and its
	# font -- is settled before it's used to center the rotate/shrink pivot.
	# Same Godot quirk menu_screen.gd's identical comment documents: a
	# freshly-changed Control's size isn't reliably final in the same frame.
	await get_tree().process_frame
	_label.pivot_offset = _label.size * 0.5

	_tween = create_tween()
	_tween.tween_interval(_VISIBLE_TIME)
	_tween.tween_property(_label, "rotation", _EXIT_ROTATION, _EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_label, "scale", Vector2.ZERO, _EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, _EXIT_TIME)
	await _tween.finished
