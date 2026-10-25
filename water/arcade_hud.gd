extends CanvasLayer

var controller: Node
var prompt := Label.new()
var marker := Label.new()
var lock_status := Label.new()
var ultimate_status := Label.new()


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
	root.add_child(ultimate_status)
	ultimate_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ultimate_status.offset_left = -100
	ultimate_status.offset_right = 100
	ultimate_status.offset_top = -65
	ultimate_status.offset_bottom = -35
	ultimate_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ultimate_status.add_theme_font_size_override("font_size", 20)
	ultimate_status.add_theme_color_override("font_outline_color", Color.BLACK)
	ultimate_status.add_theme_constant_override("outline_size", 3)
	ultimate_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.text = "+"
	marker.size = Vector2(64, 64)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 48)
	marker.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	marker.add_theme_color_override("font_outline_color", Color.BLACK)
	marker.add_theme_constant_override("outline_size", 3)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lock_status)
	lock_status.text = "Not locked on"
	lock_status.size = Vector2(180, 28)
	lock_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_status.add_theme_font_size_override("font_size", 18)
	lock_status.add_theme_color_override("font_outline_color", Color.BLACK)
	lock_status.add_theme_constant_override("outline_size", 3)
	lock_status.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	prompt.hide()
	marker.hide()
	lock_status.hide()
	ultimate_status.hide()
	if not controller.active() or Net.is_spectating() or Net.input_blocked_by_menu():
		return
	var id := multiplayer.get_unique_id() if Net.is_online() else 1
	var player = controller._body(id)
	if player == null or player._unconscious or player.movement_locked:
		return
	_update_target(player)
	var kills: int = controller.ultimate.charges.get(id, 0)
	ultimate_status.text = "Ult ready" if kills >= 3 else "Ult  %d / 3" % kills
	ultimate_status.show()
	if controller.ultimate.holding(player):
		ultimate_status.text = "Ult"
		lock_status.hide()
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


func _update_target(player) -> void:
	var target: int = 0 if controller.ultimate.holding(player) else controller.pick_target(player)
	var at: Vector2 = player.Controller.aim_position(player)
	if target != 0:
		at = VR.project_ui_position(controller._body(target).global_position, player._camera)
	var bounds := get_viewport().get_visible_rect().grow(-8.0)
	marker.position = (at - marker.size * 0.5).clamp(bounds.position, bounds.end - marker.size)
	marker.show()
	lock_status.visible = target == 0
	var status_position := marker.position + Vector2((marker.size.x - lock_status.size.x) * 0.5, marker.size.y + 4.0)
	if status_position.y + lock_status.size.y > bounds.end.y:
		status_position.y = marker.position.y - lock_status.size.y - 4.0
	lock_status.position = status_position.clamp(bounds.position, bounds.end - lock_status.size)
