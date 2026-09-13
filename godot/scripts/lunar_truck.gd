extends "res://scripts/lunar_lorry.gd"
## Eight-wheel unmanned cargo rover, using the same physical drive as Lorry.
const TRUCK_SCENE := preload("res://assets/track/lunar_support_rover_lod.glb")

func _build_visuals() -> void:
	model = TRUCK_SCENE.instantiate()
	add_child(model)
	var box := _combined_aabb(_all_meshes(model))
	if box.size.x > box.size.z:
		model.rotation.y = -PI * 0.5
	model.scale *= 6.0 / maxf(box.size.x, box.size.z)
	box = _combined_aabb(_all_meshes(model))
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)

func _wheel_mesh_names() -> Array:
	# Godot's GLTF importer strips the special "wheel" suffix from these names.
	return ["track_00", "track_01", "track_02", "track_03",
		"track_04", "track_05", "track_06", "track_07"]

func _fit_pod() -> void:
	pass

func _place_collider_and_mass() -> void:
	var meshes := [_named(model, "track_chassis"), _named(model, "track_cabin")]
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes:
		for i in 8:
			var p := to_local(mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(i))
			if first:
				bounds = AABB(p, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(p)
	var shape := BoxShape3D.new()
	shape.size = bounds.size * Vector3(0.9, 0.85, 0.95)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = bounds.get_center()
	add_child(collider)
	center_of_mass = Vector3(0, wheel_radius, 0)
	mass = 3600.0
	for wheel in vwheels:
		wheel.suspension_max_force = mass * LUNAR_GRAVITY * 3.0 / vwheels.size()

func _unhandled_input(_event: InputEvent) -> void:
	pass
