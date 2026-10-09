extends Node

const TIME_TO_CHANGE_SIZE = 0.25
# multipliers for size
const HOVERED_MULT = 1.1
const CLICKED_MULT = 0.95
const NORMAL_MULT = 1.0
# basebutton not button the_button tscns root is a texturebutton and button texturebutton are siblings
@onready var my_button: BaseButton = get_parent()
# not created here as a single onready tween a tween is single use once
var _tween: Tween

func _ready() -> void:
	# 1 triggered when the mouse enters the button area hover start
	my_button.mouse_entered.connect(_on_button_hovered)

	# 2 triggered when the mouse leaves the button area hover end
	my_button.mouse_exited.connect(_on_button_unhovered)

	# 3 triggered immediately when the mouse clicks down
	my_button.button_down.connect(_on_button_down)

	# 4 triggered when the mouse click is released
	my_button.button_up.connect(_on_button_up)

	# 5 standard full click event down up combo
	my_button.pressed.connect(_on_button_pressed)

# callback functions

func _on_button_hovered() -> void:
	_animate_to(HOVERED_MULT)

func _on_button_unhovered() -> void:
	_animate_to(NORMAL_MULT)

func _on_button_down() -> void:
	_animate_to(CLICKED_MULT)

func _on_button_up() -> void:
	_animate_to(NORMAL_MULT)

func _on_button_pressed() -> void:
	_animate_to(NORMAL_MULT)

# scale is a vector2 its a control property so the target needs to be
func _animate_to(mult: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(my_button, "scale", Vector2.ONE * mult, TIME_TO_CHANGE_SIZE)


# called every frame delta is the elapsed time since the previous frame
func _process(delta: float) -> void:
	pass
