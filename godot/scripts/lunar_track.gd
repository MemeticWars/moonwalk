extends Node3D

# Low-poly support rover built from the segmented HQ source. Unlike the merged
# source GLB, each of its eight wheels remains a separate node for animation.
const TRACK_SCENE := preload("res://assets/track/lunar_support_rover_lod.glb")
const SUPPORT_SCALE := 6.0
const FOLLOW_DISTANCE := 15.0
const GROUND_OFFSET := 3.05

var terrain: Node
var leader: Node3D
var model: Node3D
var wheels: Array[Node3D] = []
var last_position := Vector3.INF

func _ready() -> void:
	name = "LunarSupportTrack"
	model = TRACK_SCENE.instantiate()
	model.rotation.y = -PI * 0.5
	model.scale = Vector3.ONE * SUPPORT_SCALE
	add_child(model)
	_collect_parts(model)
	call_deferred("_place_behind_leader")

func _process(delta: float) -> void:
	if leader == null or not is_instance_valid(leader):
		return
	var desired := leader.global_position + leader.global_basis.z * FOLLOW_DISTANCE
	if terrain != null:
		desired.y = terrain.height_at(desired.x, desired.z) + GROUND_OFFSET
	var previous := global_position
	global_position = global_position.lerp(desired, minf(delta * 1.7, 1.0))
	var toward_leader := leader.global_position - global_position
	toward_leader.y = 0.0
	if toward_leader.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-toward_leader.x, -toward_leader.z), minf(delta * 3.0, 1.0))
	if last_position != Vector3.INF:
		var roll := global_position.distance_to(previous) / 1.25
		for wheel in wheels:
			wheel.rotate_z(roll)
	last_position = global_position

func _place_behind_leader() -> void:
	if leader == null or not is_instance_valid(leader):
		return
	var start := leader.global_position + leader.global_basis.z * FOLLOW_DISTANCE
	if terrain != null:
		start.y = terrain.height_at(start.x, start.z) + GROUND_OFFSET
	global_position = start
	look_at(leader.global_position, Vector3.UP, true)

func _collect_parts(node: Node) -> void:
	if node is MeshInstance3D:
		if node.name.to_lower() == "cube":
			node.visible = false
		elif node.name.begins_with("track_wheel_"):
			wheels.append(node)
		else:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_collect_parts(child)
