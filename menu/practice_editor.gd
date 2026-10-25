extends Control

var target: Node3D
var _previous_blocked := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
@onready var _panel: PanelContainer = $Backdrop/Panel
@onready var _move: OptionButton = $Backdrop/Panel/Scroll/Fields/Move
@onready var _infinite: CheckButton = $Backdrop/Panel/Scroll/Fields/Infinite
@onready var _lifeguard: CheckButton = $Backdrop/Panel/Scroll/Fields/Lifeguard
@onready var _red: Button = $Backdrop/Panel/Scroll/Fields/Team/Red
@onready var _blue: Button = $Backdrop/Panel/Scroll/Fields/Team/Blue


func _ready() -> void:
	add_to_group("controller_modal")
	_previous_blocked = Net._input_blocked_by_menu
	_previous_mouse_mode = Input.mouse_mode
	Net._input_blocked_by_menu = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$Backdrop/Panel/Scroll/Fields/Title.text = target.practice.display_name
	for label in target.practice.MOVE_NAMES:
		_move.add_item(label)
	_move.select(target.practice.move)
	_infinite.button_pressed = target.practice.infinite_stamina
	_lifeguard.button_pressed = target.is_lifeguard
	_red.button_pressed = target.team == target.Team.RED
	_blue.button_pressed = target.team == target.Team.BLUE
	$Backdrop/Panel/Scroll/Fields/Actions/Apply.pressed.connect(_apply)
	$Backdrop/Panel/Scroll/Fields/Actions/Cancel.pressed.connect(queue_free)
	resized.connect(_fit_panel)
	_fit_panel()
	_move.grab_focus()


func _fit_panel() -> void:
	_panel.size = Vector2(minf(400, maxf(80, size.x - 32)), minf(404, maxf(80, size.y - 32)))
	_panel.position = (size - _panel.size) * 0.5


func _input(event: InputEvent) -> void:
	if _move.get_popup().visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		queue_free()


func _process(_delta: float) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or Net.is_online():
		queue_free()


func _apply() -> void:
	if is_instance_valid(target) and not target.is_queued_for_deletion() and not Net.is_online():
		target.team = target.Team.BLUE if _blue.button_pressed else target.Team.RED
		target.practice.configure(_move.selected, _infinite.button_pressed, _lifeguard.button_pressed)
	queue_free()


func _exit_tree() -> void:
	Net._input_blocked_by_menu = _previous_blocked
	Input.mouse_mode = _previous_mouse_mode
