extends Camera3D

@export var move_speed := 10.0
@export var sprint_multiplier := 4.0
@export var mouse_sensitivity := 0.002

var yaw := 0.0
var pitch := 0.0

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity

		pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))

		rotation = Vector3(pitch, yaw, 0)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta):
	var speed = move_speed

	if Input.is_key_pressed(KEY_SHIFT):
		speed *= sprint_multiplier

	var direction = Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		direction -= transform.basis.z

	if Input.is_key_pressed(KEY_S):
		direction += transform.basis.z

	if Input.is_key_pressed(KEY_A):
		direction -= transform.basis.x

	if Input.is_key_pressed(KEY_D):
		direction += transform.basis.x

	if Input.is_key_pressed(KEY_E):
		direction += transform.basis.y

	if Input.is_key_pressed(KEY_Q):
		direction -= transform.basis.y

	if direction != Vector3.ZERO:
		global_position += direction.normalized() * speed * delta
