extends SceneTree

const Network := preload("res://scripts/highway_network.gd")
const Roads := preload("res://scripts/road_streamer.gd")
const Lorry := preload("res://scripts/lunar_lorry.gd")
var failures := 0

class TestTerrain extends Node:
	var center := Vector2i.ZERO
	func height_at(x: float, z: float) -> float:
		return 3.0 * sin(x / 45.0) + 2.0 * cos(z / 35.0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/colonies.json"))
	var routes := Network.build(data.locations)
	var expected := 0
	for i in data.locations.size():
		for j in range(i + 1, data.locations.size()):
			if Network.distance_km(data.locations[i], data.locations[j]) < 700.0:
				expected += 1
	check(routes.size() == expected + 3, "Every eligible pair must have exactly one route")
	var seen := {}
	for route in routes:
		check(route.distance_km < 700.0 or Network.is_farside_connection(route.a, route.b), "Only the three farside pairs bypass the threshold")
		check(not seen.has(route.id), "No duplicate connection")
		seen[route.id] = true
	var farside_pairs := ["Chang'e Relay--Blooming Flower", "Chang'e Relay--Daedalus Port", "Blooming Flower--Daedalus Port"]
	for pair in farside_pairs:
		check(seen.has(pair), "Missing farside connection: " + pair)
	var a := {"name": "a", "latitude": 0.0, "longitude": 0.0}
	for distance in [699.999, 700.0, 700.001]:
		var b := {"name": "b", "latitude": 0.0, "longitude": rad_to_deg(distance / Network.RADIUS_KM)}
		check(Network.build([a, b]).size() == (1 if distance < 700.0 else 0), "Boundary of 700 km")
	var ground := TestTerrain.new()
	root.add_child(ground)
	var road := Roads.new()
	road.terrain = ground
	road.lane_width = 2.0 * Lorry.highway_vehicle_width()
	check(road.lane_width > 5.0, "Measured vehicle width must be in world metres")
	road._bake_route("curve", [Vector2(-180, 0), Vector2(0, 0), Vector2(130, 100), Vector2(240, 100)], 0.2)
	var segments: Array = []
	for tile in road.descriptors_by_tile.values():
		segments.append_array(tile)
	segments.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.index < y.index)
	var max_grade := 0.0
	for i in segments.size():
		var s: Dictionary = segments[i]
		var delta: Vector3 = s.b - s.a
		var grade := absf(delta.y) / Vector2(delta.x, delta.z).length()
		max_grade = maxf(max_grade, grade)
		check(grade <= 0.0601, "Uphill and downhill grade <= 6%")
		check(s.na.y > 0.99 and s.nb.y > 0.99, "Upward, smooth surface normals")
		if i > 0:
			var previous: Dictionary = segments[i - 1]
			check(previous.b == s.a and previous.rb == s.ra and previous.nb == s.na, "Exact shared panel edges and normals")
	var key: Vector2i = road.descriptors_by_tile.keys()[0]
	var near := road._build_road_tile(key, 0)
	var far := road._build_road_tile(key, 1)
	root.add_child(near)
	root.add_child(far)
	check(near.get_child(0).mesh.get_faces() == far.get_child(0).mesh.get_faces(), "LOD cannot change the road surface")
	await physics_frame
	await physics_frame
	var s: Dictionary = road.descriptors_by_tile[key][0]
	var query := PhysicsRayQueryParameters3D.create(s.position + Vector3.UP * 10, s.position - Vector3.UP * 10)
	var hit := root.world_3d.direct_space_state.intersect_ray(query)
	check(not hit.is_empty(), "Road must be driveable from above")
	if not hit.is_empty():
		check(absf(hit.position.y - s.position.y) < 0.05, "Collision follows actual deck")
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/roads/world_routes.json"))
	check(catalogue.routes.size() == routes.size(), "Exported catalogue matches the live network")
	print("HIGHWAY TEST: %d failures; %d connections; lorry %.3f m; lane %.3f m; max grade %.5f" % [failures, routes.size(), road.lane_width * 0.5, road.lane_width, max_grade])
	near.free()
	far.free()
	road.free()
	ground.free()
	quit(1 if failures else 0)
