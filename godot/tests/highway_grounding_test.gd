extends SceneTree

const Terrain := preload("res://scripts/lunar_terrain.gd")
const Roads := preload("res://scripts/road_streamer.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/colonies.json"))
	for colony: Dictionary in data.locations:
		if not OS.get_cmdline_user_args().is_empty() and colony.name not in OS.get_cmdline_user_args():
			continue
		var terrain := Terrain.new()
		terrain.colony = colony
		root.add_child(terrain)
		var roads := Roads.new()
		roads.terrain = terrain
		roads.active_colony = colony.name
		roads.build_interchanges = false
		root.add_child(roads)
		await physics_frame
		var local_clearances: Array[float] = []
		var local_segments: Array[Dictionary] = []
		for segments: Array in roads.descriptors_by_tile.values():
			for segment: Dictionary in segments:
				if not segment.has("kind"):
					local_clearances.append(float(segment.clearance))
					local_segments.append(segment)
		if not local_clearances.is_empty():
			local_clearances.sort()
			var median: float = local_clearances[local_clearances.size() / 2]
			var elevated := 0
			for clearance: float in local_clearances:
				if clearance > 1.4:
					elevated += 1
			check(median < 5.0, "%s roads must stay near the terrain (median %.2f m)" % [colony.name, median])
			check(elevated * 2 < local_clearances.size(), "%s supports must be local, not the default road form" % colony.name)
			var max_grade := 0.0
			for segment: Dictionary in local_segments:
				var delta: Vector3 = segment.b - segment.a
				max_grade = maxf(max_grade, absf(delta.y) / Vector2(delta.x, delta.z).length())
			check(max_grade <= Roads.MAX_GRADE + 0.0002, "%s local road grade %.3f exceeds 6%%" % [colony.name, max_grade])
			var by_route := {}
			for segments: Array in roads.descriptors_by_tile.values():
				for segment: Dictionary in segments:
					if segment.has("kind"):
						continue
					if not by_route.has(segment.route):
						by_route[segment.route] = []
					by_route[segment.route].append(segment)
			for route_id: String in by_route:
				by_route[route_id].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)
				var first: Dictionary = by_route[route_id].front()
				var last: Dictionary = by_route[route_id].back()
				var direct := Vector2(first.a.x, first.a.z).distance_to(Vector2(last.b.x, last.b.z))
				var length := 0.0
				for segment: Dictionary in by_route[route_id]:
					length += Vector2(segment.b.x - segment.a.x, segment.b.z - segment.a.z).length()
				var natural_rise := absf(terrain.natural_height(last.b.x, last.b.z) - terrain.natural_height(first.a.x, first.a.z))
				if natural_rise / maxf(1.0, direct) > Roads.SWITCHBACK_TRIGGER_GRADE:
					check(length > direct * 1.2, "%s steep route must gain length with switchbacks" % route_id)
				print("GROUNDING ", colony.name, " / ", route_id, " length=", snappedf(length, 1.0),
					" direct=", snappedf(direct, 1.0), " median=", snappedf(median, 0.01))
		for route_id: String in roads.far_grounding_by_route:
			var stats: Dictionary = roads.far_grounding_by_route[route_id]
			check(float(stats.median_clearance) < 5.0, "%s far road must stay near terrain" % route_id)
			print("  FAR ", route_id, " segments=", stats.segments, " median=", snappedf(stats.median_clearance, 0.01), " max=", snappedf(stats.max_clearance, 0.01))
		roads.free()
		terrain.free()
	print("HIGHWAY GROUNDING TEST: ", failures, " failures")
	quit(1 if failures else 0)
