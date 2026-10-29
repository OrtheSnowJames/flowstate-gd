extends Control

const BUTTON := preload("res://the_button.tscn")

var list: VBoxContainer
var code: LineEdit
var _blocked := false


func _ready() -> void:
	add_to_group("controller_modal")
	_blocked = Net._input_blocked_by_menu
	Net._input_blocked_by_menu = true
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 32
	scroll.offset_right = -32
	scroll.offset_top = 24
	scroll.offset_bottom = -24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	center.add_child(list)
	resized.connect(_resize_list)
	_resize_list()
	CouchParty.changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	Net._input_blocked_by_menu = _blocked


func _resize_list() -> void:
	list.custom_minimum_size.x = minf(440.0, maxf(0.0, size.x - 80.0))


func label(text: String) -> void:
	var item := Label.new()
	item.text = text
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(item)


func button(text: String, callback: Callable, disabled := false) -> void:
	var row := Control.new()
	row.custom_minimum_size.y = 110
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(row)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	var item = BUTTON.instantiate()
	holder.add_child(item)
	item.button_text = text
	item.disabled = disabled
	item.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	holder.modulate.a = 0.4 if disabled else 1.0
	item.pressed.connect(callback)
	var fit := func() -> void:
		var factor := minf(1.0, row.size.x / (item.size.x * 1.1))
		holder.size = item.size
		holder.scale = Vector2.ONE * factor
		holder.position = (row.size - item.size * factor) * 0.5
	row.resized.connect(fit)
	fit.call()


func refresh() -> void:
	var previous := code.text if is_instance_valid(code) else ""
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	label("Couch Room " + CouchParty.code if CouchParty.active() else "Couch Rooms")
	if CouchParty.active():
		for member in CouchParty.members.values():
			label("%s  %s" % [member.name, "(bean bag)" if member.seat == 3 else ""])
		var mic := CheckButton.new()
		mic.text = "Microphone"
		mic.custom_minimum_size.y = 44
		mic.button_pressed = VoiceChat.enabled()
		mic.toggled.connect(VoiceChat.set_enabled)
		list.add_child(mic)
		if CouchParty._meta_ready:
			button("Invite Friends", CouchParty.invite_meta_friends, not CouchParty.can_invite_meta_friends())
		button("Leave Room", CouchParty.leave)
	else:
		button("Create Room", CouchParty.create_room, CouchParty.busy)
		code = LineEdit.new()
		code.placeholder_text = "Room code"
		code.max_length = 6
		code.text = previous
		code.custom_minimum_size.y = 52
		code.alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(code)
		button("Join Room", func(): CouchParty.join_room(code.text), CouchParty.busy)
	label(CouchParty.message)
	button("Cancel" if CouchParty.busy else "Back", func():
		if CouchParty.busy:
			CouchParty.leave()
		queue_free())
	for child in list.find_children("*", "BaseButton", true, false):
		if not child.disabled:
			child.grab_focus()
			break


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if CouchParty.busy:
			CouchParty.leave()
		queue_free()
