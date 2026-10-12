extends Node3D

const SPEED := 30.0
const RANGE := 30.0
const BUBBLE_SHADER := preload("res://water/bubble_beam.gdshader")

var key := ""
var origin := Vector3.ZERO
var direction := Vector3.FORWARD
var travelled := 0.0
var caster_path := NodePath()
var simulate_hits := false
var _bubbles: MultiMesh


func _ready() -> void:
	global_position = origin + direction * travelled
	look_at(global_position + direction, Vector3.RIGHT if absf(direction.y) > 0.98 else Vector3.UP)
	var material := ShaderMaterial.new()
	material.shader = BUBBLE_SHADER
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = material
	_bubbles = MultiMesh.new()
	_bubbles.transform_format = MultiMesh.TRANSFORM_3D
	_bubbles.mesh = sphere
	_bubbles.instance_count = 9
	for i in range(_bubbles.instance_count):
		var offset := Vector3(sin(i * 2.4) * 0.06, cos(i * 2.4) * 0.06, i * 0.28)
		var scale_factor := 0.75 + (i % 3) * 0.15
		_bubbles.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_factor), offset))
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = _bubbles
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	_update_bubbles()


func _physics_process(delta: float) -> void:
	if Net._round_over or Net.round_state != Net.RoundState.PLAYING:
		_expire()
		return
	var step := minf(SPEED * delta, RANGE - travelled)
	var next := global_position + direction * step
	if simulate_hits:
		var query := PhysicsRayQueryParameters3D.create(global_position, next, 1)
		var caster := get_node_or_null(caster_path) as CollisionObject3D
		if caster:
			query.exclude = [caster.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			get_parent().finish_pelt(key, hit.collider)
			return
	travelled += step
	global_position = next
	_update_bubbles()
	if travelled >= RANGE:
		_expire()


func _update_bubbles() -> void:
	_bubbles.visible_instance_count = mini(_bubbles.instance_count, 1 + int(travelled / 0.28))


func _expire() -> void:
	if simulate_hits:
		get_parent().finish_pelt(key)
	else:
		get_parent().net_remove_pelt(key)
