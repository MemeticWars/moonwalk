extends Node3D

const Network := preload("res://scripts/highway_network.gd")
const HighwayMesh := preload("res://scripts/highway_mesh.gd")
const Lamps := preload("res://scripts/highway_lamps.gd")
const Lorry := preload("res://scripts/lunar_lorry.gd")
const TILE := 64.0
const NEAR_RADIUS := 2
const FAR_RADIUS := 4
const MAX_GRADE := 0.06
## Sanity bound for how steep real lunar terrain can plausibly get, not a
## limit this highway ever tries to match. Apollo-era soil-mechanics samples
## put the lunar regolith's angle of repose at roughly 30-50 deg depending on
## grain shape/depth; LOLA slope statistics show the vast majority of the
## surface under ~35 deg, with steeper faces confined to fresh, localised
## crater walls/scarps rather than the kind of extended terrain a road runs
## across. 35 deg (~70% grade) is used here as that "typical stable maximum".
## It matters because it is well above MAX_GRADE (6%, an engineering choice
## for a driveable road, same order as a real highway) -- so real ground can
## legitimately climb faster than this road is allowed to follow. When it
## does, the deck must go elevated on piers rather than either hugging the
## slope (breaking MAX_GRADE) or getting left buried under it.
const MAX_NATURAL_SLOPE_DEG := 35.0
const PLANNING_STEP := 8.0
const PLANNING_MARGIN := 64.0
const SLOPE_COST := 22.0
const HOLLOW_COST := 9.0
const CORRIDOR_COST := 0.00035
const DETOUR_SLOPE := 0.06
const DETOUR_HOLLOW := 3.0
const SAMPLE_STEP := 4.0
const SECTOR_REACH := 1400.0
## Beyond the collision-streamed sector, retain a sparse visible continuation
## of every strategic road. It avoids creating thousands of physics panels.
const FAR_LOD_REACH := 20000.0
const FAR_LOD_STEP := 96.0
## Local sector-frame anchor for the colony's town square, not a geographic
## coordinate — every sector uses this same local origin.
const SECTOR_ORIGIN := Vector2(-9, -14)
const TychoSite := preload("res://scripts/tycho_site.gd")

var terrain: Node
var active_colony := "Silesia"
var lane_width := 0.0
var world_routes: Array[Dictionary] = []
var descriptors_by_tile: Dictionary = {}
var loaded: Dictionary = {}
var lamp_descriptors_by_tile: Dictionary = {}
## route.id -> minimum lamp station (m from the route start). Used to keep
## highway lamp posts out of a built structure that sits right at the start,
## e.g. Tycho's dome gate -- see _bake_sector_routes.
var lamp_min_station_by_route: Dictionary = {}
var center := Vector2i(999999, 999999)
var interchange_center := Vector3.ZERO
var interchange_links: Array[Dictionary] = []
var ground_exits: Array[Dictionary] = []
var full_segment_count := 0
var far_segment_count := 0
var far_lod: Node3D

func _ready() -> void:
	name = "RoadStreamer"
	lane_width = 2.0 * Lorry.highway_vehicle_width()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/colonies.json"))
	world_routes = Network.build(data.locations)
	_bake_sector_routes()
	preload("res://scripts/highway_interchange.gd").build(self)
	lamp_descriptors_by_tile = Lamps.layout(descriptors_by_tile, lane_width + 0.4, lamp_min_station_by_route)
	_build_far_lod()
	center = terrain.center
	call_deferred("_sync_tiles")

func _process(_delta: float) -> void:
	if terrain != null and terrain.center != center:
		center = terrain.center
		_sync_tiles()

## Local sector-frame point every baked route/far-LOD measures its stations
## from. Every colony but Tycho places its town square right at SECTOR_ORIGIN,
## so that generic anchor still applies. Tycho's dome no longer sits there --
## it was relocated onto the crater's central peak -- so its own highway
## anchor tracks TychoSite.CENTER instead, via the same fixed dome-to-anchor
## offset the original site happened to coincide with.
func town_square_origin() -> Vector2:
	if active_colony == "Tycho Station":
		return TychoSite.CENTER + TychoSite.HIGHWAY_ANCHOR_OFFSET
	return SECTOR_ORIGIN

func _bake_sector_routes() -> void:
	# Only one colony's sector is resident at a time. The local corridors
	# follow actual initial great-circle bearings; distant colonies are never
	# miniaturized here.
	var origin := town_square_origin()
	for route: Dictionary in world_routes:
		if route.from != active_colony and route.to != active_colony:
			continue
		var source: Dictionary = route.a if route.from == active_colony else route.b
		var destination: Dictionary = route.b if route.from == active_colony else route.a
		var lat1 := deg_to_rad(float(source.latitude))
		var lat2 := deg_to_rad(float(destination.latitude))
		var lon := deg_to_rad(float(destination.longitude) - float(source.longitude))
		var bearing := atan2(sin(lon) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon))
		var direction := Vector2(sin(bearing), -cos(bearing))
		# Tycho's main carriageway starts outside the dome. The airlock reaches it
		# through a separate access road, so a motorway deck never crosses the gate.
		# Cut back to 350 (was 400) after the 2026-09-13 site move north/west:
		# real DEM coverage along this bearing now runs out barely past the gate
		# (see tycho_site.gd's own note), so extending the paved near-field deck
		# further just puts more of it on procedural fallback ground for little
		# benefit. Kept well past the ground_pin's own 120 m blend radius and the
		# lamp system's 85 m minimum station (both measured from `start`), or the
		# deck goes fully flat / loses its lamps entirely. A temporary trim, not
		# a re-solved fit; revisit together with the gate/apron grading if the
		# site moves again.
		var tycho := active_colony == "Tycho Station"
		var start := origin + direction * (150.0 if tycho else 90.0)
		var goal := origin + direction * (350.0 if tycho else SECTOR_REACH)
		# Leave a broad rail-free opening around the shared city/cosmoport junction.
		# It sits 25 m beyond the Tycho motorway start; the dome gate itself is no
		# longer part of the carriageway.
		var pin: Dictionary = {"center": start, "radius": 120.0, "level": terrain.city_level,
			"rails_gap": 25.0, "rails_gap_half": 55.0} if tycho else {}
		if tycho:
			lamp_min_station_by_route[route.id] = 85.0
		_bake_route(route.id, _follow_safe_ground([start, goal]), 0.15, pin)

func _route_endpoint(route_id: String) -> Vector3:
	var result := Vector3.INF
	var last_index := -1
	for segments: Array in descriptors_by_tile.values():
		for segment: Dictionary in segments:
			if segment.route == route_id and int(segment.index) > last_index:
				last_index = int(segment.index)
				result = segment.b
	return result

func _build_far_lod() -> void:
	if far_lod != null:
		far_lod.queue_free()
	far_lod = Node3D.new()
	far_lod.name = "FarHighwayLOD"
	add_child(far_lod)
	var origin := town_square_origin()
	for route: Dictionary in world_routes:
		if route.from != active_colony and route.to != active_colony:
			continue
		var source: Dictionary = route.a if route.from == active_colony else route.b
		var destination: Dictionary = route.b if route.from == active_colony else route.a
		var lat1 := deg_to_rad(float(source.latitude))
		var lat2 := deg_to_rad(float(destination.latitude))
		var lon := deg_to_rad(float(destination.longitude) - float(source.longitude))
		var bearing := atan2(sin(lon) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon))
		var direction := Vector2(sin(bearing), -cos(bearing))
		var first := _route_endpoint(route.id)
		if first == Vector3.INF:
			continue
		var reach := minf(float(route.distance_km) * 1000.0, FAR_LOD_REACH)
		var start_distance := Vector2(first.x - origin.x, first.z - origin.y).dot(direction)
		if reach <= start_distance + 1.0:
			continue
		var segments: Array = []
		var count := ceili((reach - start_distance) / FAR_LOD_STEP)
		var right2d := Vector2(-direction.y, direction.x)
		var half_width := lane_width + 0.4
		# Required height at each station, sampled across the FULL deck width
		# (not just the centreline) -- real lunar cross-slope near a crater
		# rim/peak can tilt the ground enough, over just this width, that a
		# centreline-only sample leaves the uphill lane buried in it.
		var points2d: Array[Vector2] = [Vector2(first.x, first.z)]
		var heights := PackedFloat32Array([first.y])
		for i in range(1, count + 1):
			var station := minf(reach, start_distance + FAR_LOD_STEP * float(i))
			var point_2d := origin + direction * station
			var required := -INF
			for across in range(-3, 4):
				var p := point_2d + right2d * half_width * float(across) / 3.0
				required = maxf(required, terrain.height_at(p.x, p.y) + 0.15)
			points2d.append(point_2d)
			heights.append(required)
		# Two-sided max-grade envelope, same technique _bake_route uses: only
		# ever raises a station's height, so a slope steeper than MAX_GRADE
		# (well within what real lunar terrain can do -- see
		# MAX_NATURAL_SLOPE_DEG above) lifts the deck onto piers instead of
		# either breaking the grade limit or ending up under the regolith.
		for i in range(1, heights.size()):
			heights[i] = maxf(heights[i], heights[i - 1] - MAX_GRADE * points2d[i].distance_to(points2d[i - 1]))
		for i in range(heights.size() - 2, -1, -1):
			heights[i] = maxf(heights[i], heights[i + 1] - MAX_GRADE * points2d[i].distance_to(points2d[i + 1]))
		var previous := Vector3(points2d[0].x, heights[0], points2d[0].y)
		for i in range(1, heights.size()):
			var current := Vector3(points2d[i].x, heights[i], points2d[i].y)
			var tangent := (current - previous).normalized()
			var right := tangent.cross(Vector3.UP).normalized()
			segments.append({"index": i - 1, "a": previous, "b": current, "ra": right, "rb": right, "na": Vector3.UP, "nb": Vector3.UP, "position": (previous + current) * 0.5, "route": route.id, "paint": false, "rails": true, "half_width": half_width, "clearance": current.y - terrain.height_at(current.x, current.z)})
			previous = current
		if not segments.is_empty():
			var visual := MeshInstance3D.new()
			visual.name = "FarDeck_" + route.id
			visual.mesh = HighwayMesh.deck(segments, half_width)
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far_lod.add_child(visual)
			# Rails + periodic support piers wherever clearance runs high --
			# same HighwayMesh.fittings() the near-field collision tiles use,
			# just without the vertical near-side posts (near=false).
			for s: Dictionary in segments:
				HighwayMesh.fittings(far_lod, s, half_width - 0.1, false)
	_batch_fittings(far_lod)

func _follow_safe_ground(waypoints: Array[Vector2]) -> Array[Vector2]:
	# The authored waypoints describe the strategic connection. Each leg is
	# solved over the local DEM so it goes around crater rims, steep walls and
	# enclosed hollows instead of blindly cutting through them.
	var result: Array[Vector2] = []
	if waypoints.is_empty():
		return result
	result.append(waypoints[0])
	for index in range(waypoints.size() - 1):
		var leg := _plan_ground_leg(waypoints[index], waypoints[index + 1])
		for point in leg:
			if result.back().distance_to(point) > 0.5:
				result.append(point)
	return result

func _plan_ground_leg(start: Vector2, goal: Vector2) -> Array[Vector2]:
	# A connection is straight by default. The graph search is reserved for a
	# genuinely hazardous feature, rather than letting small DEM noise turn a
	# city-to-city route into a wandering path.
	if not _leg_needs_detour(start, goal):
		return [goal]
	var low := start.min(goal) - Vector2.ONE * PLANNING_MARGIN
	var high := start.max(goal) + Vector2.ONE * PLANNING_MARGIN
	var origin := Vector2i(floori(low.x / PLANNING_STEP), floori(low.y / PLANNING_STEP))
	var end_cell := Vector2i(ceili(high.x / PLANNING_STEP), ceili(high.y / PLANNING_STEP))
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(origin, end_cell - origin + Vector2i.ONE)
	grid.cell_size = Vector2.ONE * PLANNING_STEP
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	grid.update()
	var direct := (goal - start).normalized()
	for z in range(grid.region.position.y, grid.region.end.y):
		for x in range(grid.region.position.x, grid.region.end.x):
			var p := Vector2(x, z) * PLANNING_STEP
			var h: float = terrain.height_at(p.x, p.y)
			var east: float = terrain.height_at(p.x + PLANNING_STEP, p.y)
			var south: float = terrain.height_at(p.x, p.y + PLANNING_STEP)
			var slope := maxf(absf(east - h), absf(south - h)) / PLANNING_STEP
			# A crater floor is lower than its immediate surroundings. This makes
			# wide bowls expensive even where their walls are not very steep.
			var ring: float = (terrain.height_at(p.x - 12.0, p.y) + terrain.height_at(p.x + 12.0, p.y) + terrain.height_at(p.x, p.y - 12.0) + terrain.height_at(p.x, p.y + 12.0)) * 0.25
			var hollow := maxf(0.0, ring - h - 0.5)
			# The corridor term prevents accidental sweeping curves. It yields only
			# when avoiding a crater floor or a cliff is materially safer.
			var lateral := absf(direct.cross(p - start))
			var corridor := lateral * lateral * CORRIDOR_COST
			grid.set_point_weight_scale(Vector2i(x, z), 1.0 + slope * SLOPE_COST + hollow * HOLLOW_COST + corridor)
	var start_cell := Vector2i(roundi(start.x / PLANNING_STEP), roundi(start.y / PLANNING_STEP))
	var goal_cell := Vector2i(roundi(goal.x / PLANNING_STEP), roundi(goal.y / PLANNING_STEP))
	var cells := grid.get_id_path(start_cell, goal_cell)
	if cells.is_empty():
		return [goal]
	var path: Array[Vector2] = []
	for cell in cells:
		var point := Vector2(cell) * PLANNING_STEP
		if path.size() < 2 or not _same_heading(path[path.size() - 2], path.back(), point):
			path.append(point)
		else:
			path[path.size() - 1] = point
	if not path.is_empty():
		path[0] = start
		path[path.size() - 1] = goal
	return path

func _leg_needs_detour(start: Vector2, goal: Vector2) -> bool:
	var distance := start.distance_to(goal)
	var steps := maxi(1, ceili(distance / PLANNING_STEP))
	var previous: float = terrain.height_at(start.x, start.y)
	for i in range(1, steps + 1):
		var p := start.lerp(goal, float(i) / float(steps))
		var h: float = terrain.height_at(p.x, p.y)
		var slope := absf(h - previous) / maxf(0.01, distance / steps)
		var ring: float = (terrain.height_at(p.x - 12.0, p.y) + terrain.height_at(p.x + 12.0, p.y) + terrain.height_at(p.x, p.y - 12.0) + terrain.height_at(p.x, p.y + 12.0)) * 0.25
		if slope > DETOUR_SLOPE or ring - h > DETOUR_HOLLOW:
			return true
		previous = h
	return false

func _same_heading(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var first := (b - a).normalized()
	var second := (c - b).normalized()
	return first.dot(second) > 0.999

func _bake_route(route_id: String, points: Array[Vector2], surface_offset: float, ground_pin: Dictionary = {}) -> void:
	if terrain == null or points.size() < 2:
		return
	# Rounded horizontal alignment, preserving the connection endpoints.
	for iteration in 4:
		var rounded: Array[Vector2] = [points[0]]
		for i in range(points.size() - 1):
			rounded.append(points[i].lerp(points[i + 1], 0.25))
			rounded.append(points[i].lerp(points[i + 1], 0.75))
		rounded.append(points.back())
		points = rounded
	var curve := Curve3D.new()
	curve.bake_interval = SAMPLE_STEP
	for p in points:
		curve.add_point(Vector3(p.x, 0, p.y))
	var samples := PackedVector3Array()
	var length := curve.get_baked_length()
	var count := maxi(2, ceili(length / SAMPLE_STEP))
	for i in range(count + 1):
		samples.append(curve.sample_baked(length * float(i) / count))
	# A wide lorry road cannot inherit tight grid-scale bends: relax curvature
	# until the inside edge has ample radius and cannot fold over itself.
	var minimum_radius := lane_width * 6.0
	for iteration in 600:
		var worst := 0.0
		for i in range(1, samples.size() - 1):
			var incoming := samples[i] - samples[i - 1]
			var outgoing := samples[i + 1] - samples[i]
			worst = maxf(worst, incoming.normalized().angle_to(outgoing.normalized()) / maxf(0.01, (incoming.length() + outgoing.length()) * 0.5))
		if worst <= 1.0 / minimum_radius:
			break
		var relaxed := samples.duplicate()
		for i in range(1, samples.size() - 1):
			relaxed[i] = samples[i] * 0.5 + (samples[i - 1] + samples[i + 1]) * 0.25
		samples = relaxed
	# Restore uniform arc-length sampling after smoothing.
	curve.clear_points()
	for p in samples:
		curve.add_point(p)
	length = curve.get_baked_length()
	count = maxi(2, ceili(length / SAMPLE_STEP))
	samples.clear()
	for i in range(count + 1):
		samples.append(curve.sample_baked(length * float(i) / count))
	var rights := PackedVector3Array()
	var heights := PackedFloat32Array()
	for i in samples.size():
		var tangent := (samples[mini(i + 1, count)] - samples[maxi(0, i - 1)]).normalized()
		var right := tangent.cross(Vector3.UP).normalized()
		rights.append(right)
		var required := -INF
		# Check the full carriageway width, not just the centreline.
		for across in range(-8, 9):
			var p := samples[i] + right * (lane_width + 0.4) * float(across) / 8.0
			required = maxf(required, terrain.height_at(p.x, p.z) + surface_offset)
		# Near a pinned colony pad, blend the road down onto the pad level so the
		# spur arrives at town level instead of on a viaduct.
		if not ground_pin.is_empty():
			var d: float = Vector2(samples[i].x, samples[i].z).distance_to(ground_pin.center)
			var blend := smoothstep(ground_pin.radius * 0.5, ground_pin.radius, d)
			required = lerpf(ground_pin.level + surface_offset, required, blend)
		heights.append(required)
	# Two-sided clearance envelope limits grade in BOTH travel directions.
	for i in range(1, heights.size()):
		heights[i] = maxf(heights[i], heights[i - 1] - MAX_GRADE * samples[i].distance_to(samples[i - 1]))
	for i in range(heights.size() - 2, -1, -1):
		heights[i] = maxf(heights[i], heights[i + 1] - MAX_GRADE * samples[i].distance_to(samples[i + 1]))
	var smoothed := PackedFloat32Array()
	for i in heights.size():
		var h := 0.0
		for offset in range(-6, 7):
			h += heights[clampi(i + offset, 0, heights.size() - 1)] / 13.0
		smoothed.append(h)
	var lift := 0.0
	for i in heights.size():
		lift = maxf(lift, heights[i] - smoothed[i])
	for i in samples.size():
		samples[i].y = smoothed[i] + lift
	# Nail the pinned end onto the pad, then let the ramp climb away toward the
	# baked profile no faster than MAX_GRADE so the transition itself stays in
	# spec (a plain distance-blend would re-introduce grade where the pad level
	# and the natural collar diverge).
	if not ground_pin.is_empty():
		var pad_y: float = ground_pin.level + surface_offset
		var flat_r: float = ground_pin.radius * 0.22
		var anchor := 0
		var anchor_d := INF
		for i in samples.size():
			var d: float = Vector2(samples[i].x, samples[i].z).distance_to(ground_pin.center)
			if d < anchor_d:
				anchor_d = d
				anchor = i
			if d <= flat_r:
				samples[i].y = pad_y
		# Climb away from the anchor no faster than MAX_GRADE, measured on the
		# horizontal like the grade test does (not 3D chord length).
		for i in range(anchor + 1, samples.size()):
			var run_f: float = Vector2(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z).length()
			samples[i].y = clampf(samples[i].y, samples[i - 1].y - MAX_GRADE * run_f, samples[i - 1].y + MAX_GRADE * run_f)
		for i in range(anchor - 1, -1, -1):
			var run_b: float = Vector2(samples[i].x - samples[i + 1].x, samples[i].z - samples[i + 1].z).length()
			samples[i].y = clampf(samples[i].y, samples[i + 1].y - MAX_GRADE * run_b, samples[i + 1].y + MAX_GRADE * run_b)
	var normals := PackedVector3Array()
	for i in samples.size():
		var tangent := (samples[mini(i + 1, count)] - samples[maxi(0, i - 1)]).normalized()
		normals.append(rights[i].cross(tangent).normalized())
	var has_rails_gap: bool = not ground_pin.is_empty() and ground_pin.has("rails_gap")
	for i in count:
		var midpoint := (samples[i] + samples[i + 1]) * 0.5
		var descriptor := {"id": "%s:%05d" % [route_id, i], "index": i,
			"a": samples[i], "b": samples[i + 1], "ra": rights[i], "rb": rights[i + 1],
			"na": normals[i], "nb": normals[i + 1], "route": route_id, "position": midpoint,
			"clearance": midpoint.y - terrain.height_at(midpoint.x, midpoint.z)}
		if has_rails_gap:
			var station: float = Vector2(midpoint.x, midpoint.z).distance_to(ground_pin.center)
			descriptor["rails"] = absf(station - ground_pin.rails_gap) > ground_pin.rails_gap_half
		var key := Vector2i(floori(midpoint.x / TILE), floori(midpoint.z / TILE))
		if not descriptors_by_tile.has(key):
			descriptors_by_tile[key] = []
		descriptors_by_tile[key].append(descriptor)

func _sync_tiles() -> void:
	if terrain == null:
		return
	var wanted := {}
	for key: Vector2i in descriptors_by_tile:
		var distance := maxi(absi(key.x - center.x), absi(key.y - center.y))
		if distance <= FAR_RADIUS:
			wanted[key] = 0 if distance <= NEAR_RADIUS else 1
	for key: Vector2i in loaded.keys():
		if not wanted.has(key) or loaded[key].get_meta("lod") != wanted[key]:
			loaded[key].queue_free()
			loaded.erase(key)
	for key: Vector2i in wanted:
		if not loaded.has(key):
			var tile := _build_road_tile(key, wanted[key])
			loaded[key] = tile
			add_child(tile)
	full_segment_count = 0
	far_segment_count = 0
	for tile in loaded.values():
		if tile.get_meta("lod") == 0:
			full_segment_count += int(tile.get_meta("segments"))
		else:
			far_segment_count += int(tile.get_meta("segments"))

func _build_road_tile(key: Vector2i, lod: int) -> Node3D:
	var root := Node3D.new()
	root.name = "RoadTile_%d_%d_LOD%d" % [key.x, key.y, lod]
	root.set_meta("lod", lod)
	var segments: Array = descriptors_by_tile[key]
	root.set_meta("segments", segments.size())
	var visual := MeshInstance3D.new()
	visual.name = "ContinuousConcreteDeck"
	visual.mesh = HighwayMesh.deck(segments, lane_width + 0.4)
	root.add_child(visual)
	if lod == 0:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		# Paint is visual only: avoid parallel overlapping collision surfaces.
		var arrays: Array = visual.mesh.surface_get_arrays(0)
		shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
		collision.shape = shape
		body.add_child(collision)
		root.add_child(body)
	for descriptor: Dictionary in segments:
		HighwayMesh.fittings(root, descriptor, float(descriptor.get("half_width", lane_width + 0.4)) - 0.1, lod == 0)
	_batch_fittings(root)
	if lamp_descriptors_by_tile.has(key):
		root.add_child(Lamps.build(lamp_descriptors_by_tile[key], lod == 0))
	return root

func _batch_fittings(root: Node3D) -> void:
	# One draw call per fitting material and tile, not one per rail or post.
	# Also reused for FarHighwayLOD, whose own per-route deck meshes are named
	# "FarDeck_<route id>" instead of the single "ContinuousConcreteDeck".
	var groups := {}
	for child in root.get_children():
		if not child is MeshInstance3D or child.name == "ContinuousConcreteDeck" or child.name.begins_with("FarDeck_"):
			continue
		var material: Material = child.mesh.surface_get_material(0)
		if not groups.has(material):
			var builder := SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builder.set_material(material)
			groups[material] = builder
		groups[material].append_from(child.mesh, 0, child.transform)
		child.free()
	for builder: SurfaceTool in groups.values():
		var instance := MeshInstance3D.new()
		instance.mesh = builder.commit()
		root.add_child(instance)
