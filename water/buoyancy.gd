# generic buoyancy drop this node as a child of any rigidbody3d and it floats
extends Node3D
class_name Buoyancy

# water node exposing get_height_at defaults to the first node in group water
@export var water_path: NodePath
# probe offsets in the bodys local space leave empty to auto generate a grid
@export var probe_points: PackedVector3Array = PackedVector3Array()
# depth m at which a probe is considered fully submerged full lift
@export var submerge_depth: float = 1.0
# upward acceleration per unit submersion must exceed gravity to float the resting waterline is
@export var buoyancy_accel: float = 22.0
# linear resistance while submerged slows drift kills bounce
@export var linear_drag: float = 2.2
# angular resistance while submerged settles rocking
@export var angular_drag: float = 1.5

var _body: RigidBody3D
var _water: Node
var _gravity: float = 9.8


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("Buoyancy: parent must be a RigidBody3D.")
		set_physics_process(false)
		return

	if water_path:
		_water = get_node_or_null(water_path)
	if _water == null:
		_water = get_tree().get_first_node_in_group("water")
	if _water == null or not _water.has_method("get_height_at"):
		push_error("Buoyancy: no water node with get_height_at() found (set water_path or add one to group \"water\").")
		set_physics_process(false)
		return

	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

	if probe_points.is_empty():
		probe_points = _auto_probes()


func _physics_process(_delta: float) -> void:
	var n := probe_points.size()
	if n == 0:
		return
	var inv_n := 1.0 / float(n)
	var com := _body.global_position # default center of mass sits at the origin

	for local_p in probe_points:
		var world_p := _body.to_global(local_p)
		var water_y: float = _water.get_height_at(world_p)
		var depth := water_y - world_p.y
		if depth <= 0.0:
			continue # this probe is above the surface no lift
		var submersion := clampf(depth / submerge_depth, 0.0, 1.0)
		var offset := world_p - com

		# archimedes lift shared across probes so the total matches the body
		var lift := Vector3.UP * submersion * buoyancy_accel * _body.mass * inv_n
		_body.apply_force(lift, offset)

		# drag at the probe uses the points real velocity so it damps spin too
		var v_at := _body.linear_velocity + _body.angular_velocity.cross(offset)
		_body.apply_force(-v_at * linear_drag * _body.mass * inv_n, offset)

	# a little extra angular damping so bodies settle instead of rocking forever
	if _is_touching_water():
		_body.angular_velocity *= 1.0 / (1.0 + angular_drag * _delta_safe())


func _delta_safe() -> float:
	# _physics_process delta isnt captured above unused param use the fixed step
	return 1.0 / float(Engine.physics_ticks_per_second)


func _is_touching_water() -> bool:
	for local_p in probe_points:
		var world_p := _body.to_global(local_p)
		if _water.get_height_at(world_p) - world_p.y > 0.0:
			return true
	return false


# spread probes across the bottom half of the parents collision shape so lift produces
func _auto_probes() -> PackedVector3Array:
	var ext := Vector3(0.5, 0.5, 0.5)
	for child in _body.get_children():
		if child is CollisionShape3D and child.shape != null:
			ext = _shape_half_extents(child.shape)
			break
	var pts := PackedVector3Array()
	# four lower corners centre at 60 down gives lift tilt without spikes
	var y := -ext.y * 0.6
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append(Vector3(sx * ext.x * 0.7, y, sz * ext.z * 0.7))
	pts.append(Vector3(0.0, y, 0.0))
	# match the fully submerged depth to the bodys height by default
	submerge_depth = maxf(ext.y * 1.5, 0.3)
	return pts


func _shape_half_extents(shape: Shape3D) -> Vector3:
	if shape is BoxShape3D:
		return shape.size * 0.5
	if shape is SphereShape3D:
		return Vector3(shape.radius, shape.radius, shape.radius)
	if shape is CapsuleShape3D:
		return Vector3(shape.radius, shape.height * 0.5, shape.radius)
	if shape is CylinderShape3D:
		return Vector3(shape.radius, shape.height * 0.5, shape.radius)
	return Vector3(0.5, 0.5, 0.5)
