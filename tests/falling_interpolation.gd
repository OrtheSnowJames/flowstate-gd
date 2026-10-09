extends Node

var player: Node3D
var last_physics_y := 0.0
var last_view_y := 0.0
var smoothed_frames := 0
var sampled_frames := 0
var failed := false


func _ready() -> void:
	set_process(false)
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 10
	Engine.max_fps = 120
	Net._round_over = true
	player = Net._players_root().get_node("1")
	player.position = Vector3(14, 30, 0)
	player.linear_velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.get_global_transform_interpolated()
	_expect(player.is_physics_interpolated_and_enabled(), "local player physics interpolation enabled")
	_expect(not player._cam_pivot.is_physics_interpolated(), "camera uses frame updates")
	last_physics_y = player.global_position.y
	last_view_y = last_physics_y
	set_process(true)
	await get_tree().create_timer(1.0).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/flowstate-falling.png")
	await get_tree().create_timer(2.5).timeout
	set_process(false)
	_expect(smoothed_frames > 10, "falling moves visually between physics ticks")
	_expect(player.global_position.y < 10.0, "drop reaches the water")
	print("falling frames ", sampled_frames, " interpolated between ticks ", smoothed_frames)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/flowstate-falling-water.png")
	print("PASS falling interpolation" if not failed else "FAIL falling interpolation")
	get_tree().quit(1 if failed else 0)


func _process(_delta: float) -> void:
	var physics_y := player.global_position.y
	var view_y := player.get_global_transform_interpolated().origin.y
	if is_equal_approx(physics_y, last_physics_y) and absf(view_y - last_view_y) > 0.001:
		smoothed_frames += 1
	last_physics_y = physics_y
	last_view_y = view_y
	sampled_frames += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
