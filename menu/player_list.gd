# view players panel lists every peers name net name_of coloured by team and blurs
extends Control

const PLAYER_SCRIPT := preload("res://water/player.gd")

# matches water player gds own _team_colors exactly duplicated rather than reached across scripts that
const _RED := Color("d92d2d")
const _BLUE := Color("2d6bd9")

signal _close_requested

@onready var _rows: VBoxContainer = $Panel/VBox/Rows
@onready var _button_host: Control = $Panel/VBox/ButtonHost


func _ready() -> void:
	visible = false


# blurs the background in shows the live roster and waits for close then blurs
func open() -> void:
	await Transition.blur_in()
	visible = true
	_refresh()
	Net.lobby_changed.connect(_refresh)
	_button_host.show_buttons([
		{"label": "Close", "on_press": func() -> void: _close_requested.emit()},
	])

	await _close_requested

	if Net.lobby_changed.is_connected(_refresh):
		Net.lobby_changed.disconnect(_refresh)
	await Transition.blur_out()
	queue_free()


func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var ids := Net._teams.keys()
	ids.sort()
	for id in ids:
		var row := Label.new()
		row.text = Net.name_of(id)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 22)
		row.add_theme_color_override("font_color",
			_BLUE if Net.team_of(id) == PLAYER_SCRIPT.Team.BLUE else _RED)
		_rows.add_child(row)
