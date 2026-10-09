# reusable list of buttons engine for the menu every screen root play settings is
extends Control

const _THE_BUTTON := preload("res://the_button.tscn")
const _THE_STEPPER := preload("res://the_stepper.tscn")

# vertical gap between buttons on top of each buttons own real height
const _ROW_GAP := 18.0
# how far below its resting spot a button starts or ends up mid transition
const _SLIDE_DISTANCE := 60.0
const _OUT_DURATION := 0.2
const _IN_DURATION := 0.3
# delay between each buttons own in animation starting for a staggered rise instead of
const _STAGGER := 0.05
const _SCROLL_PADDING := 24.0

var _buttons: Array[Control] = []
# bumped on every show_buttons call each call captures its own value and checks it
var _gen := 0


func _ready() -> void:
	resized.connect(_layout_buttons)


# specs array of dictionaries two row kinds picked by type defaults to button when
func show_buttons(specs: Array) -> void:
	_gen += 1
	var my_gen := _gen
	await _clear_current()
	if my_gen != _gen:
		return
	await _spawn(specs, my_gen)


func _clear_current() -> void:
	if _buttons.is_empty():
		return
	var old := _buttons
	_buttons = []
	var tw := create_tween()
	tw.set_parallel(true)
	for btn in old:
		tw.tween_property(btn, "position:y", btn.position.y + _SLIDE_DISTANCE, _OUT_DURATION)
		tw.tween_property(btn, "modulate:a", 0.0, _OUT_DURATION)
	await tw.finished
	for btn in old:
		btn.queue_free()


func _spawn(specs: Array, my_gen: int) -> void:
	var new_buttons: Array[Control] = []
	for spec in specs:
		# untyped on purpose button_text row_label amount_text the button and stepper interface scripts own exports
		var btn
		if spec.get("type", "button") == "stepper":
			btn = _THE_STEPPER.instantiate()
			btn.modulate.a = 0.0
			add_child(btn)
			btn.row_label = spec.get("label", "")
			btn.amount_text = spec.get("value", "")
			# steppers update just their own amount_text in place instead of tearing down and rebuilding
			var on_left = spec.get("on_left")
			if on_left is Callable:
				btn.left_pressed.connect(func() -> void:
					var new_text = on_left.call()
					if new_text is String:
						btn.amount_text = new_text)
			var on_right = spec.get("on_right")
			if on_right is Callable:
				btn.right_pressed.connect(func() -> void:
					var new_text = on_right.call()
					if new_text is String:
						btn.amount_text = new_text)
		else:
			btn = _THE_BUTTON.instantiate()
			btn.modulate.a = 0.0
			add_child(btn)
			btn.button_text = spec.get("label", "")
			var on_press = spec.get("on_press")
			if on_press is Callable:
				btn.pressed.connect(on_press)
		new_buttons.append(btn)

	if my_gen != _gen:
		# a newer show_buttons call already started and if it got far enough already owns
		for btn in new_buttons:
			btn.queue_free()
		return

	_buttons = new_buttons
	if new_buttons.is_empty():
		return

	# one frame so every buttons real size driven by its own texture which this
	await get_tree().process_frame

	var total_height := 0.0
	for btn in new_buttons:
		total_height += btn.size.y
	total_height += float(maxi(new_buttons.size() - 1, 0)) * _ROW_GAP
	if get_parent() is ScrollContainer:
		custom_minimum_size.y = total_height + _SCROLL_PADDING * 2.0
		await get_tree().process_frame
		if my_gen != _gen:
			return
	var y := (size.y - total_height) * 0.5

	var tw := create_tween()
	tw.set_parallel(true)
	for i in new_buttons.size():
		var btn := new_buttons[i]
		var rest_pos := Vector2((size.x - btn.size.x) * 0.5, y)
		btn.position = rest_pos + Vector2(0.0, _SLIDE_DISTANCE)
		tw.tween_property(btn, "position", rest_pos, _IN_DURATION) \
			.set_delay(i * _STAGGER).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate:a", 1.0, _IN_DURATION).set_delay(i * _STAGGER)
		y += btn.size.y + _ROW_GAP
	await tw.finished
	if my_gen == _gen:
		_layout_buttons()


func _layout_buttons() -> void:
	var total_height := float(maxi(_buttons.size() - 1, 0)) * _ROW_GAP
	for btn in _buttons:
		total_height += btn.size.y
	var y := (size.y - total_height) * 0.5
	for btn in _buttons:
		btn.position = Vector2((size.x - btn.size.x) * 0.5, y)
		y += btn.size.y + _ROW_GAP
