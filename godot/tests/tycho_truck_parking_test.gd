extends SceneTree

class FlatTerrain extends Node3D:
	var pads: Array = []
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func add_city_pad(center: Vector2, radius: float, blend: float, sample_radius: float, level) -> void:
		pads.append({"center": center, "radius": radius, "blend": blend, "sample_radius": sample_radius, "level": level})

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := FlatTerrain.new()
	root.add_child(terrain)
	var port := preload("res://scripts/tycho_cosmoport.gd").new()
	port.terrain = terrain
	port.gate_dir = Vector2(0, -1)
	port.highway_dir = Vector2(0.2239, -0.9746)
	port.highway_origin = Vector2(-9, -39)
	port.test_mode = true
	root.add_child(port)
	assert(terrain.pads.size() == 1, "Truck parking must grade its ground before creating the deck")
	assert(terrain.pads[0].radius >= 38)
	var stands: PackedVector3Array = port.truck_stands_global()
	assert(stands.size() == 2, "Parking must provide exactly two freight stands")
	assert(stands[0].distance_to(stands[1]) > 16.0, "Large trucks need separate parking bays")
	assert(stands[0].distance_to(Vector3.ZERO) > 100.0, "Parking must stay outside the airlock")
	var parking_bodies: Array = port.find_children("*", "StaticBody3D", true, false)
	assert(parking_bodies.size() > 0, "Parking deck must have collision")
	var truck := preload("res://scripts/lunar_truck.gd").new()
	truck.terrain = terrain
	root.add_child(truck)
	await create_timer(2).timeout
	var box := truck._combined_aabb(truck._all_meshes(truck.model))
	assert(maxf(maxf(box.size.x, box.size.y), box.size.z) > 11.5, "Truck must scale to 12 m")
	assert(is_equal_approx(truck.mass, 28800.0), "Truck mass must scale with doubled dimensions")
	print("TYCHO TRUCK PARKING PASS: graded external bays, collision, 12 m freight trucks")
	quit()
