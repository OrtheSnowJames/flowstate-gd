extends Node

var failed := false

class DodgeProbe:
	extends RefCounted
	const DODGE_DOUBLE_TAP_TIME := 0.25
	var controller_dodge_taps: Dictionary = {}
	var left := 0
	var right := 0
	func _dodge_left() -> void:
		left += 1
	func _dodge_right() -> void:
		right += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var probe := DodgeProbe.new()
	var tap := InputEventJoypadButton.new()
	tap.button_index = JOY_BUTTON_DPAD_LEFT
	tap.pressed = true
	var movement = preload("res://water/player/movement.gd")
	movement.detect_dodge(probe, 1.0, tap)
	_expect(probe.left == 0, "single dpad tap does not dodge")
	tap.pressed = false
	movement.detect_dodge(probe, 1.05, tap)
	_expect(probe.left == 0, "release does not count as a tap")
	tap.pressed = true
	movement.detect_dodge(probe, 1.1, tap)
	_expect(probe.left == 1, "double dpad left dodges left")
	tap.button_index = JOY_BUTTON_DPAD_RIGHT
	movement.detect_dodge(probe, 1.15, tap)
	_expect(probe.right == 0, "directions have separate tap timers")
	movement.detect_dodge(probe, 1.5, tap)
	_expect(probe.right == 0, "slow taps do not dodge")
	movement.detect_dodge(probe, 1.6, tap)
	_expect(probe.right == 1, "double dpad right dodges right")
	VR.active = true
	var grip := InputEventAction.new()
	grip.action = "vr_dodge_left"
	grip.pressed = true
	movement.detect_dodge(probe, 2.0, grip)
	_expect(probe.left == 2, "vr left grip dodges without double tapping")
	grip.action = "vr_dodge_right"
	movement.detect_dodge(probe, 2.1, grip)
	_expect(probe.right == 2, "vr right grip dodges without double tapping")
	VR.active = false
	var player = Net._players_root().get_node("1")
	player.freeze = true
	player.set_physics_process(false)
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = 0.1
	player.Controller.track(player, event)
	_expect(not player.using_controller, "stick drift does not switch modes")
	event.axis_value = 1.0
	player.Controller.track(player, event)
	_expect(player.using_controller, "stick switches to controller")
	Input.action_press("pad_move_right", 0.7)
	_expect(player.Controller.movement_input(player).y < 0, "sideways stick produces movement")
	player.controller_angles.x = 0.0
	player._turn_from_input(1.0)
	_expect((-player.transform.basis.z).distance_to(Vector3.RIGHT) < 0.01, "movement follows camera direction")
	Input.action_release("pad_move_right")
	var yaw: float = player.controller_angles.x
	Input.action_press("pad_look_right")
	player._camera_pivot_change(0.1)
	_expect(player.controller_angles.x < yaw, "right stick turns camera")
	Input.action_release("pad_look_right")
	var prompt = player._ensure_revive_prompt()
	prompt.show_for(player, player._camera, true)
	_expect(prompt.get_node("Box/Row/Keycap/Key").text == "Right D-pad", "controller revive label")
	prompt.show_for(player, player._camera, false)
	_expect(prompt.get_node("Box/Row/Keycap/Key").text == "R", "label changes with the same revive target")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	player.Controller.track(player, key)
	_expect(not player.using_controller, "keyboard restores keyboard mode")
	var revive := InputEventJoypadButton.new()
	revive.button_index = JOY_BUTTON_DPAD_RIGHT
	_expect(InputMap.event_is_action(revive, "revive"), "existing revive binding preserved")
	print("FAIL controller input" if failed else "PASS controller input")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
