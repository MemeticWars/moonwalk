extends RefCounted
## A shared level junction, two tangent-matched links and two ground ramps.
const ColonyUtil := preload("res://scripts/colony_util.gd")

static func build(roads: Node) -> void:
	var mouths: Array[Dictionary] = []
	for tile in roads.descriptors_by_tile.values():
		for segment: Dictionary in tile:
			if segment.index == 0:
				mouths.append(segment)
	if mouths.size() < 2:
		return
	mouths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.route < b.route)
	var first: Vector3 = mouths[0].a
	var second: Vector3 = mouths[1].a
	var axis := Vector3(second.x - first.x, 0, second.z - first.z).normalized()
	var cross_axis := axis.cross(Vector3.UP)
	var hub := (first + second) * 0.5 + cross_axis * 300.0
	hub.y = (first.y + second.y) * 0.5
	var extent: float = roads.lane_width * 2.5
	var width: float = roads.lane_width + 0.4
	roads.interchange_center = hub
	var prefix: String = ColonyUtil.slug(roads.active_colony)
	# Split the hub precisely at the ramp mouths so no rail crosses an exit.
	var cuts: Array[float] = [-extent, -width, width, extent]
	for i in 3:
		var a := hub + axis * cuts[i]
		var b := hub + axis * cuts[i + 1]
		store(roads, prefix + "-junction", i, a, b, cross_axis, cross_axis,
			Vector3.UP, Vector3.UP, extent, {"rails": i != 1, "paint": false, "kind": "junction"})
	for i in 2:
		var mouth: Dictionary = mouths[i]
		var sign_value := -1.0 if i == 0 else 1.0
		var target := hub + axis * extent * sign_value
		var start: Vector3 = mouth.a
		var tangent: Vector3 = (mouth.a - mouth.b).normalized()
		var arrival := -axis * sign_value
		var handle := start.distance_to(target) * 0.45
		var points := PackedVector3Array()
		var count := maxi(40, ceili(start.distance_to(target) / 2.0))
		for j in range(count + 1):
			var t := float(j) / count
			points.append(start.bezier_interpolate(start + tangent * handle, target - arrival * handle, target, t))
		# Use arc length for the vertical Hermite profile: Bezier parameter speed
		# must not turn a gentle height change into a steep short segment.
		var stations := PackedFloat32Array([0.0])
		for j in range(1, points.size()):
			stations.append(stations[-1] + Vector2(points[j].x - points[j - 1].x, points[j].z - points[j - 1].z).length())
		var total := stations[-1]
		for j in points.size():
			var t := stations[j] / total
			# The main road now stays near its own terrain, so the two mouths can
			# start at noticeably different levels. A constant arc-length grade
			# avoids the Hermite overshoot that used to push these short links over
			# the same 6% limit enforced on the highways.
			points[j].y = lerpf(start.y, target.y, t)
		var id := prefix + "-link-%d" % i
		ribbon(roads, id, points, width, -mouth.ra, arrival.cross(Vector3.UP), mouth.na, Vector3.UP, "connector")
		roads.interchange_links.append({"route": id, "source": mouth.route, "start": start, "end": target})
	for sign_value: float in [-1.0, 1.0]:
		var direction := cross_axis * sign_value
		var start := hub + direction * extent
		# Search nearby landing sites, rather than extending a ramp indefinitely
		# down the DEM's macro slope. Both lanes land on a level prepared apron.
		var end := start
		var best := INF
		for distance: float in [80.0, 100.0, 120.0, 150.0, 180.0, 240.0, 300.0, 360.0, 480.0]:
			for degrees in range(-85, 86, 5):
				var heading := direction.rotated(Vector3.UP, deg_to_rad(float(degrees)))
				var candidate := start + heading * distance
				candidate.y = roads.terrain.height_at(candidate.x, candidate.z)
				var natural_y := candidate.y
				candidate.y = clampf(natural_y, start.y - distance * 0.025, start.y - 1.0)
				var earthwork := absf(natural_y - candidate.y)
				var rise := absf(candidate.y - start.y)
				if Vector2(candidate.x, candidate.z).distance_to(roads.SECTOR_ORIGIN) < 60.0:
					continue
				if not clear_landing(roads, start, direction, candidate, width):
					continue
				var score := earthwork * 20.0 + rise * 8.0 + distance * 0.02 + absf(degrees) * 0.03
				if score < best:
					best = score
					end = candidate
		assert(best < INF, "No safe ground landing found for %s exit" % roads.active_colony)
		var arrival := Vector3(end.x - start.x, 0, end.z - start.z).normalized()
		var handle := Vector2(end.x - start.x, end.z - start.z).length() * 0.4
		var points := PackedVector3Array()
		var count := ceili(handle * 2.5 / 2.0)
		for j in range(count + 1):
			var t := float(j) / count
			points.append(start.bezier_interpolate(start + direction * handle, end - arrival * handle, end, t))
		var stations := PackedFloat32Array([0.0])
		for j in range(1, points.size()):
			stations.append(stations[-1] + Vector2(points[j].x-points[j-1].x, points[j].z-points[j-1].z).length())
		for j in points.size():
			var t := stations[j] / stations[-1]
			points[j].y = lerpf(start.y, end.y, t*t*(3.0-2.0*t))
		var id := prefix + "-ground-exit-%d" % roads.ground_exits.size()
		ribbon(roads, id, points, width, direction.cross(Vector3.UP), arrival.cross(Vector3.UP), Vector3.UP, Vector3.UP, "ramp")
		roads.ground_exits.append({"route": id, "start": start, "end": points[-1], "width": width * 2.0})
		if roads.terrain.has_method("add_road_grading"):
			roads.terrain.add_road_grading(points, width + 2.0)
	if roads.terrain.has_method("refresh_road_grading"):
		roads.terrain.refresh_road_grading()

static func clear_landing(roads: Node, start: Vector3, direction: Vector3, end: Vector3, width: float, ignore_route: String = "") -> bool:
	# The two -link- connectors are interchange-internal structure that fans out
	# from the same hub as the ramps; treating them as foreign roads blocks every
	# candidate on bearings where they sweep through the exit search. Silesia keeps
	# the stricter check: its hand-authored sector is the validated reference and
	# the general fix shifts its exit-candidate choice past the 4cm collision gate.
	var skip_connectors: bool = roads.active_colony != "Silesia"
	var arrival := Vector3(end.x - start.x, 0, end.z - start.z).normalized()
	var handle := Vector2(end.x - start.x, end.z - start.z).length() * 0.4
	var probes: Array[Vector3] = []
	for i in range(2, 21):
		probes.append(start.bezier_interpolate(start + direction * handle, end - arrival * handle, end, float(i) / 20.0))
	for distance in [10.0, 20.0, 40.0]:
		probes.append(end + arrival * distance)
	for p in probes:
		var point := Vector2(p.x, p.z)
		if point.distance_to(roads.SECTOR_ORIGIN) < 35.0:
			return false
		var key := Vector2i(floori(p.x / roads.TILE), floori(p.z / roads.TILE))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for s: Dictionary in roads.descriptors_by_tile.get(key + Vector2i(dx, dz), []):
					if s.get("kind") == "junction" or (skip_connectors and s.get("kind") == "connector") or s.route == ignore_route:
						continue
					var a := Vector2(s.a.x, s.a.z)
					var b := Vector2(s.b.x, s.b.z)
					var t := clampf((point - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
					if point.distance_to(a.lerp(b, t)) < width + float(s.get("half_width", width)) + 2.0:
						return false
	return true

static func ribbon(roads: Node, id: String, points: PackedVector3Array, width: float,
		first_right: Vector3, last_right: Vector3, first_normal: Vector3, last_normal: Vector3, kind: String) -> void:
	var rights := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]).normalized()
		var right := tangent.cross(Vector3.UP).normalized()
		rights.append(right)
		normals.append(right.cross(tangent).normalized())
	rights[0] = first_right
	rights[-1] = last_right
	normals[0] = first_normal
	normals[-1] = last_normal
	for i in range(points.size() - 1):
		store(roads, id, i, points[i], points[i + 1], rights[i], rights[i + 1], normals[i], normals[i + 1], width,
			{"kind": kind, "rails": kind != "ramp" or i < points.size() - 13})

static func store(roads: Node, id: String, index: int, a: Vector3, b: Vector3, ra: Vector3, rb: Vector3,
		na: Vector3, nb: Vector3, width: float, options: Dictionary) -> void:
	var mid := (a + b) * 0.5
	var descriptor := {"id": "%s:%05d" % [id, index], "route": id, "index": index,
		"a": a, "b": b, "ra": ra, "rb": rb, "na": na, "nb": nb, "half_width": width,
		"position": mid, "clearance": mid.y - roads.terrain.height_at(mid.x, mid.z)}
	descriptor.merge(options)
	var key := Vector2i(floori(mid.x / roads.TILE), floori(mid.z / roads.TILE))
	if not roads.descriptors_by_tile.has(key):
		roads.descriptors_by_tile[key] = []
	roads.descriptors_by_tile[key].append(descriptor)
	if options.get("kind") != "ramp" and roads.terrain.has_method("add_road_cut"):
		roads.terrain.add_road_cut(a, b, width)
