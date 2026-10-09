extends Control

signal submitted(ip: String, port: int)

@onready var _panel: PanelContainer = $Margin/Scroll/Center/Panel
@onready var _title: Label = $Margin/Scroll/Center/Panel/VBox/Title
@onready var _address_row: VBoxContainer = $Margin/Scroll/Center/Panel/VBox/Address
@onready var _address: LineEdit = $Margin/Scroll/Center/Panel/VBox/Address/Input
@onready var _port: LineEdit = $Margin/Scroll/Center/Panel/VBox/Port/Input
@onready var _error: Label = $Margin/Scroll/Center/Panel/VBox/Error
@onready var _buttons: Control = $Margin/Scroll/Center/Panel/VBox/Buttons

var _hosting := false
var _submitted := false


func _ready() -> void:
	resized.connect(_resize_panel)
	_resize_panel()
	_address.text_submitted.connect(func(_text: String) -> void: _submit())
	_port.text_submitted.connect(func(_text: String) -> void: _submit())


func open(hosting: bool) -> void:
	_hosting = hosting
	_title.text = "Host Server" if hosting else "Join Server"
	_address_row.visible = not hosting
	_address.text = Net.join_ip
	_port.text = str(Net.PORT)
	_buttons.show_buttons([
		{"label": "Host" if hosting else "Join", "on_press": _submit},
		{"label": "Cancel", "on_press": queue_free},
	])
	await get_tree().process_frame
	var first := _port if hosting else _address
	first.grab_focus()
	first.select_all()


func _submit() -> void:
	if _submitted:
		return
	var address := _address.text.strip_edges()
	var port_text := _port.text.strip_edges()
	if not _hosting and address.is_empty():
		_error.text = "Enter an IP address"
		_address.grab_focus()
		return
	if not port_text.is_valid_int() or port_text.to_int() < 1 or port_text.to_int() > 65535:
		_error.text = "Port must be between 1 and 65535"
		_port.grab_focus()
		return
	_submitted = true
	submitted.emit(address, port_text.to_int())
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func _resize_panel() -> void:
	_panel.custom_minimum_size.x = minf(440.0, maxf(0.0, size.x - 64.0))
