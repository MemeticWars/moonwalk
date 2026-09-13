extends SceneTree

class TerrainStub extends Node3D:
	var city_level := 0.0

class CityFixture extends "res://scripts/tycho_city.gd":
	func _ready() -> void:
		set_process(false)
		dimensions = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "modules.json"))

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))

func _run() -> void:
	var terrain := TerrainStub.new()
	root.add_child(terrain)
	var city := CityFixture.new()
	city.terrain = terrain
	root.add_child(city)
	var actor := preload("res://tests/crawl_roof_test.gd").ProbeAgnes.new()
	root.add_child(actor)
	var fixtures := ["twin-houses", "block-of-flats", "central-building", "central-house", "l-shape-building", "l-shape-building-mirrored"]
	for index in fixtures.size():
		var asset: String = fixtures[index]
		var kind := asset.trim_suffix("-mirrored")
		city.scenes[asset] = load(city.ASSETS + asset + ".glb")
		city.descriptors.append({"kind": kind, "asset": asset, "point": Vector2(index * 150, 0), "yaw": 0.37, "lift": 0.0, "mirror": asset.ends_with("-mirrored")})
		city._build_module(index, true)
	await physics_frame
	await physics_frame
	for index in fixtures.size():
		var building: Node3D = city.loaded[index]
		check(building.get_node("Body").get_child_count() == 0, "No footprint prism may fill roof recesses: " + fixtures[index])
		var hits := 0
		var climb_starts := 0
		for height: float in [0.3, 1.0, 2.0, 4.0, 6.0, 8.0]:
			for angle in 32:
				var direction := Vector3(sin(angle * TAU / 32.0), 0, cos(angle * TAU / 32.0))
				var center := building.global_position + Vector3.UP * height
				var motion := _ray(center + direction * 65.0, center - direction * 65.0, 1)
				var facade := _ray(center + direction * 65.0, center - direction * 65.0, 2)
				check(motion.is_empty() == facade.is_empty(), "Movement and climbing must agree on openings: " + fixtures[index])
				if not facade.is_empty():
					hits += 1
					check(not motion.is_empty() and (motion.position as Vector3).distance_to(facade.position) < 0.002, "Movement must follow the actual facade at every height: " + fixtures[index])
					if is_equal_approx(height, 1.0):
						actor.global_position = facade.position + direction * (actor.collision_radius_m + actor.WALL_WALK_MARGIN)
						actor.global_position.y = building.global_position.y + 0.15
						actor.visual_yaw = atan2(-direction.x, -direction.z)
						if not actor._nearest_climb_surface().is_zero_approx(): climb_starts += 1
		for x in range(-25, 26, 2):
			for z in range(-25, 26, 2):
				var from := building.global_position + Vector3(x, 60, z)
				var to := from - Vector3.UP * 65
				var motion := _ray(from, to, 1)
				var roof := _ray(from, to, 2)
				check(motion.is_empty() == roof.is_empty(), "Roof holes must remain open: " + fixtures[index])
				if not roof.is_empty():
					check(not motion.is_empty() and (motion.position as Vector3).distance_to(roof.position) < 0.002, "Movement roof must match climbing roof: " + fixtures[index])
		check(hits > 15, "Test must sample a real building: " + fixtures[index])
		check(climb_starts >= 4, "Q must find multiple climbable walls from the walking margin: " + fixtures[index])
		print("BUILDING COLLISION: ", fixtures[index], " facade samples=", hits, " climb starts=", climb_starts)
	print("BUILDING COLLISION TEST: ", failures, " failures")
	quit(1 if failures else 0)
