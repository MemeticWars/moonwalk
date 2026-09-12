extends SceneTree
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var terrain := preload("res://scripts/lunar_terrain.gd").new()
	root.add_child(terrain)
	var roads := preload("res://scripts/road_streamer.gd").new()
	roads.terrain = terrain
	root.add_child(roads)
	check(roads.interchange_links.size() == 2, "Two links join the highway mouths")
	check(roads.ground_exits.size() == 2, "Two exits reach the ground")
	var routes := {}
	for tile in roads.descriptors_by_tile.values():
		for s: Dictionary in tile:
			if not routes.has(s.route):
				routes[s.route] = []
			routes[s.route].append(s)
	for id in routes:
		var segments: Array = routes[id]
		segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)
		var maximum := 0.0
		for i in segments.size():
			var s: Dictionary = segments[i]
			var delta: Vector3 = s.b - s.a
			maximum = maxf(maximum, absf(delta.y) / Vector2(delta.x, delta.z).length())
			if i > 0:
				check(segments[i - 1].b == s.a, "No panel gap: " + id)
				check(segments[i - 1].nb == s.na, "No normal seam: " + id)
		print(id, " max grade ", maximum)
		check(maximum <= 0.0602, "Grade <= 6%: " + id)
	for link in roads.interchange_links:
		var main: Dictionary = routes[link.source][0]
		var join: Dictionary = routes[link.route][0]
		check(join.a == main.a and join.ra == -main.ra and join.na == main.na, "Exact reversed highway connection")
		check(routes[link.route].back().nb == Vector3.UP, "Level hub join")
	for exit_data in roads.ground_exits:
		var end: Dictionary = routes[exit_data.route].back()
		var start: Dictionary = routes[exit_data.route][0]
		check(preload("res://scripts/highway_interchange.gd").clear_landing(roads, start.a, Vector3.UP.cross(start.ra), end.b, end.half_width, exit_data.route), "Ramp and runout clear of other roads")
		for across in [-1.0, 0.0, 1.0]:
			var point: Vector3 = end.b + end.rb * end.half_width * across
			check(absf(terrain.height_at(point.x, point.z) - point.y) < 0.02, "Flush ground exit across full width")
		check(not end.rails, "Exit mouth must be open")
		check(terrain.road_reserved(end.b.x, end.b.z), "No rocks at the exit")
	# Exercise actual collision meshes across the links, hub and ramp mouths.
	var fixtures := Node3D.new()
	root.add_child(fixtures)
	var probes: Array[Vector3] = [roads.interchange_center]
	var keys := {}
	for id in routes:
		if not str(id).begins_with("silesia-"):
			continue
		var segments: Array = routes[id]
		for i in range(0, segments.size(), 8):
			probes.append(segments[i].position)
		probes.append(segments[0].a)
		probes.append(segments[-1].b)
	for point in probes:
		keys[Vector2i(floori(point.x / roads.TILE), floori(point.z / roads.TILE))] = true
	for key: Vector2i in keys:
		if roads.descriptors_by_tile.has(key):
			fixtures.add_child(roads._build_road_tile(key, 0))
		fixtures.add_child(terrain._build_ground(key, 0))
	await physics_frame
	await physics_frame
	for point in probes:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point - Vector3.UP * 2)
		var hit := root.world_3d.direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "Continuous collision at " + str(point))
		if not hit.is_empty():
			check(absf(hit.position.y - point.y) < 0.04, "Collision follows road/ground transition")
	fixtures.free()
	print("INTERCHANGE TEST: ", failures, " failures")
	quit(1 if failures else 0)
