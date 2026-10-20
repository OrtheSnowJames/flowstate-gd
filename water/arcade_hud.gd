extends CanvasLayer

var controller: Node
var prompt := Label.new()
var marker := Label.new()


func _ready() -> void:
	layer = 40
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -250
	prompt.offset_right = 250
	prompt.offset_top = -180
	prompt.offset_bottom = -80
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt.add_theme_constant_override("shadow_offset_y", 2)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(marker)
	marker.text = "+"
	marker.add_theme_font_size_override("font_size", 30)
	marker.modulate = Color(1.0, 0.8, 0.2)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	prompt.hide()
	marker.hide()
	if not controller.active() or Net.is_spectating() or Net.input_blocked_by_menu():
		return
	var id := multiplayer.get_unique_id() if Net.is_online() else 1
	var player = controller._body(id)
	if player == null or player._unconscious:
		return
	var state: Dictionary = controller.view.get(id, {})
	var phase: int = state.get("phase", -1)
	var q := "Left Trigger" if VR.active else "Q"
	var e := "Right Trigger" if VR.active else "E"
	var pound := "Left Stick Click + A" if VR.active else "Shift + Space"
	var moves := "%s  Dash     %s  Ground Pound" % [q, pound]
	if VR.active:
		moves = "%s  Dash\n%s  Ground Pound" % [q, pound]
	match phase:
		controller.Phase.CLASH:
			var rival: Dictionary = controller.view.get(state.target, {})
			prompt.text = "%s\n%d : %d   |   %.1fs" % [q if state.next == 0 else e, state.score, rival.get("score", 0), maxf(state.time, 0)]
		controller.Phase.CHOICE:
			prompt.text = ("%s  Retreat\n%s  Vault" if VR.active else "%s  Retreat     %s  Vault") % [q, e]
		controller.Phase.OPEN:
			prompt.text = moves
		controller.Phase.DASH:
			prompt.text = "Dash"
		controller.Phase.SLAM:
			prompt.text = "Clash lost"
		controller.Phase.POUND:
			prompt.text = "Ground Pound"
		_:
			if not controller.airborne(player):
				return
			prompt.text = moves
	prompt.show()
	var target: int = controller.pick_target(player)
	if target != 0:
		marker.position = VR.project_ui_position(controller._body(target).global_position, player._camera) - Vector2(10, 20)
		marker.show()
