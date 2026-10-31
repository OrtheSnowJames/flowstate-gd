# name and voice preferences
extends Control

@onready var _panel: PanelContainer = $Backdrop/Panel
@onready var _title_label: Label = $Backdrop/Panel/Scroll/VBox/Title
@onready var _line_edit: LineEdit = $Backdrop/Panel/Scroll/VBox/LineEdit
@onready var _voice: CheckButton = $Backdrop/Panel/Scroll/VBox/Voice
@onready var _devices: OptionButton = $Backdrop/Panel/Scroll/VBox/Microphone
@onready var _cancel_button: Button = $Backdrop/Panel/Scroll/VBox/Actions/Cancel

var _on_submit: Callable
var _on_cancel: Callable
var _previous_blocked := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	add_to_group("controller_modal")
	_previous_blocked = Net._input_blocked_by_menu
	_previous_mouse_mode = Input.mouse_mode
	Net._input_blocked_by_menu = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resized.connect(_fit_panel)
	_fit_panel()
	$Backdrop/Panel/Scroll/VBox/Actions/Confirm.pressed.connect(_submit)
	_cancel_button.pressed.connect(_cancel)
	_devices.get_popup().about_to_popup.connect(_refresh_devices)
	_voice.toggled.connect(func(enabled: bool): _devices.disabled = not enabled)


func _exit_tree() -> void:
	Net._input_blocked_by_menu = _previous_blocked
	Input.mouse_mode = _previous_mouse_mode


func _fit_panel() -> void:
	_panel.size = Vector2(minf(480, maxf(80, size.x - 32)), minf(440, maxf(80, size.y - 32)))
	_panel.position = (size - _panel.size) * 0.5


func _refresh_devices() -> void:
	var selected := Settings.voice_device
	if _devices.selected >= 0:
		selected = _devices.get_item_text(_devices.selected)
	_devices.clear()
	var devices := AudioServer.get_input_device_list()
	if not devices.has("Default"):
		devices.insert(0, "Default")
	for device in devices:
		_devices.add_item(device)
		_devices.set_item_tooltip(_devices.item_count - 1, device)
		if device == selected:
			_devices.select(_devices.item_count - 1)
	if not devices.has(selected):
		_devices.add_item(selected)
		_devices.set_item_tooltip(_devices.item_count - 1, "Microphone unavailable")
		_devices.select(_devices.item_count - 1)


# shows the prompt pre filled with initial_text titled title calls on_submit new_text with non
func open(initial_text: String, title: String, on_submit: Callable,
		on_cancel: Callable = Callable()) -> void:
	_title_label.text = title
	_line_edit.text = initial_text
	_on_submit = on_submit
	_on_cancel = on_cancel

	_cancel_button.visible = on_cancel.is_valid()
	_voice.set_pressed_no_signal(Settings.voice_enabled)
	_devices.disabled = not Settings.voice_enabled
	_refresh_devices()

	if not _line_edit.text_submitted.is_connected(_on_line_submitted):
		_line_edit.text_submitted.connect(_on_line_submitted)

	# one frame so the lineedit genuinely exists in the tree before asking it to
	await get_tree().process_frame
	_line_edit.grab_focus()
	_line_edit.caret_column = _line_edit.text.length()


func _on_line_submitted(_text: String) -> void:
	_submit()


func _submit() -> void:
	var text := _line_edit.text.strip_edges()
	if text.is_empty():
		_flash_empty()
		return
	Settings.voice_configured = true
	Settings.voice_enabled = _voice.button_pressed
	Settings.voice_device = _devices.get_item_text(_devices.selected)
	if _on_submit.is_valid():
		_on_submit.call(text)
	VoiceChat.apply_settings()
	queue_free()


func _cancel() -> void:
	if _on_cancel.is_valid():
		_on_cancel.call()
	queue_free()


var _flash_tween: Tween

# a blank confirm doesnt close the prompt an empty name isnt legal net gds
func _flash_empty() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_line_edit.modulate = Color(1.0, 0.5, 0.5)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_line_edit, "modulate", Color.WHITE, 0.3)
