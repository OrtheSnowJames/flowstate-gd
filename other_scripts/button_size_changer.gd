extends Node

const TIME_TO_CHANGE_SIZE = 0.25
# Multipliers for size
const HOVERED_MULT = 1.1
const CLICKED_MULT = 0.95
const NORMAL_MULT = 1.0
## BaseButton, not Button: the_button.tscn's root is a TextureButton, and
## Button/TextureButton are siblings under BaseButton, not one a subtype of
## the other -- typing this as Button failed the assignment (parent is the
## wrong type), left my_button null, and every signal .connect() below then
## crashed on a null reference. BaseButton is the common ancestor that still
## has every signal and property this script actually uses.
@onready var my_button: BaseButton = get_parent()
# Not created here as a single @onready Tween: a Tween is single-use -- once
# it finishes playing, it's invalid, and every tween_property() call after
# that is silently ignored. Reused across five different signals firing
# repeatedly (hover in/out, press/release), that meant only the very first
# animation of the button's whole lifetime ever actually played. _animate_to()
# below kills and recreates it on every call instead.
var _tween: Tween

func _ready() -> void:
	# 1. Triggered when the mouse enters the button area (Hover Start)
	my_button.mouse_entered.connect(_on_button_hovered)

	# 2. Triggered when the mouse leaves the button area (Hover End)
	my_button.mouse_exited.connect(_on_button_unhovered)

	# 3. Triggered immediately when the mouse clicks down
	my_button.button_down.connect(_on_button_down)

	# 4. Triggered when the mouse click is released
	my_button.button_up.connect(_on_button_up)

	# 5. Standard full click event (Down + Up combo)
	my_button.pressed.connect(_on_button_pressed)

# --- CALLBACK FUNCTIONS ---

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

## `scale` is a Vector2 (it's a Control property), so the target needs to be
## one too -- tweening it toward a bare float was the next crash in line once
## the button/hover types stopped crashing on _ready(). Vector2.ONE * mult
## keeps X and Y scaling together, matching a single "size multiplier" knob.
func _animate_to(mult: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(my_button, "scale", Vector2.ONE * mult, TIME_TO_CHANGE_SIZE)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
