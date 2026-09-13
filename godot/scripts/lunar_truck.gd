extends "res://scripts/lunar_lorry.gd"
## Textured eight-wheel unmanned cargo rover, using the same physical drive as Lorry.
# Built by tools/prepare_lunar_truck.py from two separate Meshy exports of the
# same rover: a single fully-textured hull (its own wheel bulges are fused
# into the body mesh, no clean cut boundary) and an untextured part-segmentation
# pass whose 8 wheels are individually separable. The prep script scales the
# segmented wheels into the textured hull's frame and re-materials them as
# plain tire rubber, so they cleanly cover the hull's built-in wheel bulges.
const TRUCK_SCENE := preload("res://assets/lorry/lunar_logistics_rover_full.glb")
const LENGTH_M := 12.0
const TRUCK_WHEELS := ["wheel_0", "wheel_1", "wheel_2", "wheel_3", "wheel_4", "wheel_5", "wheel_6", "wheel_7"]

func _build_visuals() -> void:
	model = TRUCK_SCENE.instantiate()
	add_child(model)
	var box := _combined_aabb(_all_meshes(model))
	if box.size.x > box.size.z:
		model.rotation.y = -PI * 0.5
	# These are freight haulers, twice the original support-rover scale.
	model.scale *= LENGTH_M / maxf(box.size.x, box.size.z)
	box = _combined_aabb(_all_meshes(model))
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)

func _wheel_mesh_names() -> Array:
	return TRUCK_WHEELS

func _fit_pod() -> void:
	pass

func drive_engine_pull() -> float:
	# Eight driven wheels and an 8x loaded mass (doubled hull dimensions) keep
	# the same low lunar acceleration as the small Lorry, while wheel traction
	# remains the limit.
	return ENGINE_PULL * 8.0

func _place_collider_and_mass() -> void:
	# The combined donor has a single textured body plus 8 separate wheel
	# meshes. The body's complete bounds give a reliable hull envelope;
	# reduce it enough that the wheel rays, not the box, remain responsible
	# for ground contact.
	var bounds := _combined_aabb(_all_meshes(model))
	var shape := BoxShape3D.new()
	shape.size = bounds.size * Vector3(0.88, 0.54, 0.90)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = bounds.get_center() + Vector3(0.0, bounds.size.y * 0.18, 0.0)
	add_child(collider)
	center_of_mass = Vector3(0, wheel_radius, 0)
	# Doubling every dimension gives approximately eight times the loaded mass.
	mass = 28800.0
	for wheel in vwheels:
		wheel.suspension_max_force = mass * LUNAR_GRAVITY * 3.0 / vwheels.size()

func _unhandled_input(_event: InputEvent) -> void:
	pass
