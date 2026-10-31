extends RigidBody3D

@export var throw_speed := 20.0
@export var spin_speed := 12.0

@export var water: Area3D # water

var balloon_id := 0
var thrower_id := 0
var max_range := 0.0
var range_origin := Vector3.ZERO
var _age := 0.0
var _popped := false
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _snapshot_age := 0.0
var _launch_position := Vector3.ZERO
var _launch_velocity := Vector3.ZERO
var _aim_point := Vector3.ZERO
var _flight_time := 0.0
var _flight_elapsed := 0.0
var _gravity := 9.8
var _previous_hit_position := Vector3.ZERO

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 16
	continuous_cd = true
	custom_integrator = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	$PlayerHitbox.add_exception(get_parent().get_parent())
	if Net.is_online() and not multiplayer.is_server():
		freeze = true
		collision_layer = 0
		collision_mask = 0

func throw_at(target: Vector3) -> void:
	var radius: float = $CollisionShape3D.shape.radius
	_launch_position = global_position
	_aim_point = target + Vector3.UP * radius
	var offset := _aim_point - _launch_position
	_gravity = maxf(0.01, float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale)
	_flight_time = maxf(offset.length() / maxf(throw_speed, 0.01), 0.0001)
	_flight_elapsed = 0.0
	_launch_velocity = offset / _flight_time + Vector3.UP * (0.5 * _gravity * _flight_time)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3(
		randf_range(-spin_speed, spin_speed),
		randf_range(-spin_speed, spin_speed),
		randf_range(-spin_speed, spin_speed),
	)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _popped or _flight_time <= 0.0 or (Net.is_online() and not multiplayer.is_server()):
		return
	_flight_elapsed = minf(_flight_elapsed + state.step, _flight_time)
	var next := _launch_position + _launch_velocity * _flight_elapsed \
		+ Vector3.DOWN * (0.5 * _gravity * _flight_elapsed * _flight_elapsed)
	# stop at the aimed point even when the whole throw takes less than one tick
	state.linear_velocity = (next - state.transform.origin) / state.step

func touching_water() -> bool:
	return is_instance_valid(water) and water.overlaps_body(self)

func touching_player() -> bool:
	for body in get_colliding_bodies():
		if body.is_in_group("player"):
			return true
	return false

func sync_transform(pose: Transform3D, first := false) -> void:
	_from = pose if first else global_transform
	_to = pose
	_snapshot_age = 0.0
	if first:
		global_transform = pose
		_previous_hit_position = pose.origin
		reset_physics_interpolation()


func _process(delta: float) -> void:
	if Net.is_online() and not multiplayer.is_server():
		_snapshot_age += delta
		global_transform = _from.interpolate_with(_to, minf(_snapshot_age / 0.05, 1.0))


func _physics_process(delta: float) -> void:
	if _popped or (Net.is_online() and not multiplayer.is_server()):
		return
	var hitbox: ShapeCast3D = $PlayerHitbox
	hitbox.global_position = _previous_hit_position
	hitbox.target_position = hitbox.to_local(global_position)
	hitbox.force_shapecast_update()
	for i in hitbox.get_collision_count():
		var player := hitbox.get_collider(i) as Node3D
		if player == null or not player.is_in_group("player"):
			continue
		var query := PhysicsRayQueryParameters3D.create(_previous_hit_position, player.global_position,
			1, [get_rid(), player.get_rid(), get_parent().get_parent().get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		_popped = true
		Net.pop_water_balloon(self, player)
		return
	hitbox.position = Vector3.ZERO
	_previous_hit_position = global_position
	_age += delta
	var offset := Vector3(global_position.x - range_origin.x, 0.0, global_position.z - range_origin.z)
	if max_range > 0.0 and offset.length() >= max_range:
		offset = offset.limit_length(max_range)
		global_position.x = range_origin.x + offset.x
		global_position.z = range_origin.z + offset.z
		_popped = true
		Net.pop_water_balloon(self)
		return
	for body in get_colliding_bodies():
		if body == get_parent().get_parent():
			continue
		_popped = true
		Net.pop_water_balloon(self, body if body.is_in_group("player") else null)
		return
	var arrived := _flight_time > 0.0 and _flight_elapsed >= _flight_time \
		and global_position.distance_to(_aim_point) < 0.05
	if touching_water() or arrived or _age >= 10.0:
		_popped = true
		Net.pop_water_balloon(self)
