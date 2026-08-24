## Reusable "list of buttons" engine for the menu -- every screen (root,
## Play, Settings) is just a call to show_buttons() with a different list;
## no screen has its own hand-placed nodes. Every button is an instance of
## the_button.tscn (the only button type used anywhere in the menu), its text
## set via that scene's own `button_text` export and wired to a callback via
## its ordinary `pressed` signal -- nothing new to learn about "the button I
## already made."
##
## Attached to a plain Control, not a VBoxContainer: the transition animation
## drives each button's own `position` directly (see _spawn()), which a
## container would immediately fight by re-laying-out children every frame.
extends Control

const _THE_BUTTON := preload("res://the_button.tscn")
const _THE_STEPPER := preload("res://the_stepper.tscn")

## Vertical gap between buttons, on top of each button's own real height.
const _ROW_GAP := 18.0
## How far below its resting spot a button starts (or ends up) mid-transition
## -- this is the "come up from the bottom" / "slides away downward" distance.
const _SLIDE_DISTANCE := 60.0
const _OUT_DURATION := 0.2
const _IN_DURATION := 0.3
## Delay between each button's own in-animation starting, for a staggered
## rise instead of every row popping up in lockstep.
const _STAGGER := 0.05

var _buttons: Array[Control] = []
## Bumped on every show_buttons() call; each call captures its own value and
## checks it again after every await. Clicking fast enough to fire a second
## show_buttons() before the first one's out-tween/spawn finishes used to
## race: both calls would eventually reach `_buttons = new_buttons`, and
## whichever happened to finish its await last would win, silently
## discarding the *other* call's already-spawned (and by then possibly
## already-visible) buttons -- they'd stay in the tree, on screen, forever,
## since nothing referenced them in `_buttons` anymore to fade/free them
## next time around. Comparing against `_gen` after each await lets a
## superseded call notice and bail out (freeing whatever it already spawned)
## instead of clobbering a newer call's bookkeeping.
var _gen := 0


## specs: Array of Dictionaries. Two row kinds, picked by `"type"` (defaults
## to `"button"` when omitted, so every existing caller with plain
## `{"label", "on_press"}` rows keeps working unchanged):
##   - `{"label": String, "on_press": Callable}` -- the_button.tscn.
##   - `{"type": "stepper", "label": String, "value": String,
##      "on_left": Callable, "on_right": Callable}` -- the_stepper.tscn, a
##      row with a left ("-") and right ("+") arrow around a value. Unlike
##      button rows, on_left/on_right are expected to return the new amount
##      text (a String) instead of triggering a full show_buttons() rebuild
##      -- see _spawn().
## Replaces whatever's currently shown: existing rows slide down and fade
## out first; only once that finishes do the new ones spawn (already in
## their final column, offset below it and transparent) and rise + fade into
## place with a slight stagger.
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
		# Untyped on purpose: button_text/row_label/amount_text (the button
		# and stepper interface scripts' own exports) and pressed/
		# left_pressed/right_pressed (their signals) are members Control
		# doesn't statically know about -- typing this as Control would fail
		# to even parse the lines below that touch them. Appending an
		# untyped ref into the Array[Control] below still works fine; typed
		# arrays check the actual runtime value, not the expression's static
		# type.
		var btn
		if spec.get("type", "button") == "stepper":
			btn = _THE_STEPPER.instantiate()
			btn.modulate.a = 0.0
			add_child(btn)
			btn.row_label = spec.get("label", "")
			btn.amount_text = spec.get("value", "")
			# Steppers update just their own amount_text in place instead of
			# tearing down and rebuilding the whole screen on every arrow
			# press -- on_left/on_right mutate the underlying value and hand
			# back the new label text; this row is the only thing that
			# changes.
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
		# A newer show_buttons() call already started (and, if it got far
		# enough, already owns `_buttons`) while this one was still building
		# its row -- free what we just spawned instead of leaving it behind
		# unreferenced, and don't touch `_buttons` at all.
		for btn in new_buttons:
			btn.queue_free()
		return

	_buttons = new_buttons
	if new_buttons.is_empty():
		return

	# One frame so every button's real size -- driven by its own texture,
	# which this script has no reason to know the pixel dimensions of -- is
	# settled before it's used to center/stack them. A freshly instantiated
	# and parented Control's `size` isn't reliably final in the same frame.
	await get_tree().process_frame

	var total_height := 0.0
	for btn in new_buttons:
		total_height += btn.size.y
	total_height += float(maxi(new_buttons.size() - 1, 0)) * _ROW_GAP
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
