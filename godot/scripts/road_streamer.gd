extends Node3D

const Network := preload("res://scripts/highway_network.gd")
const HighwayMesh := preload("res://scripts/highway_mesh.gd")
const Lamps := preload("res://scripts/highway_lamps.gd")
const Lorry := preload("res://scripts/lunar_lorry.gd")
const TILE := 64.0
const NEAR_RADIUS := 2
const FAR_RADIUS := 4
const MAX_GRADE := 0.06
const PLANNING_STEP := 8.0
const PLANNING_MARGIN := 64.0
const SLOPE_COST := 22.0
const HOLLOW_COST := 9.0
const CORRIDOR_COST := 0.00035
const DETOUR_SLOPE := 0.06
const DETOUR_HOLLOW := 3.0
const SAMPLE_STEP := 4.0
const SECTOR_REACH := 1400.0
## A long natural slope is climbed on the ground with switchbacks. The target
## stays below MAX_GRADE so rounding the bends and small DEM irregularities do
## not immediately turn the whole climb back into a viaduct.
const SWITCHBACK_TARGET_GRADE := 0.045
const SWITCHBACK_TRIGGER_GRADE := 0.055
const SWITCHBACK_OFFSET := 240.0
const SWITCHBACK_MAX_LEGS := 31
const SWITCHBACK_LEAD := 180.0
const SWITCHBACK_ROUNDING_ALLOWANCE := 2.2
const BRIDGE_MAX_RUN := 320.0
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
var far_grounding_by_route: Dictionary = {}
var build_interchanges := true

func _ready() -> void:
	name = "RoadStreamer"
	lane_width = 2.0 * Lorry.highway_vehicle_width()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/colonies.json"))
	world_routes = Network.build(data.locations)
	_bake_sector_routes()
	if build_interchanges:
		preload("res://scripts/highway_interchange.gd").build(self)
	_register_main_road_cuts()
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
	far_grounding_by_route.clear()
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
		var half_width := lane_width + 0.4
		var far_goal := origin + direction * reach
		var alignment: Array[Vector2] = [Vector2(first.x, first.z)]
		var direct_start := alignment[0]
		var chunk_count := maxi(1, ceili(direct_start.distance_to(far_goal) / SECTOR_REACH))
		for chunk in range(chunk_count):
			var chunk_goal := direct_start.lerp(far_goal, float(chunk + 1) / float(chunk_count))
			# Far LOD is visual-only and spans tens of kilometres. Give broad
			# elevation changes the same switchback treatment without running a
			# large A* search for every unseen kilometre-sized chunk.
			var leg := _switchback_waypoints(alignment.back(), chunk_goal)
			if leg.is_empty():
				leg = [chunk_goal]
			for point: Vector2 in leg:
				if alignment.back().distance_to(point) > 0.5:
					alignment.append(point)
		var far_curve := Curve3D.new()
		far_curve.bake_interval = FAR_LOD_STEP
		for point: Vector2 in alignment:
			far_curve.add_point(Vector3(point.x, 0.0, point.y))
		var far_length := far_curve.get_baked_length()
		var count := maxi(1, ceili(far_length / FAR_LOD_STEP))
		# Required visual height at each far station.
		var points2d: Array[Vector2] = []
		var heights := PackedFloat32Array([first.y])
		for i in range(count + 1):
			var sample := far_curve.sample_baked(far_length * float(i) / float(count))
			var point_2d := Vector2(sample.x, sample.z)
			points2d.append(point_2d)
			if i == 0:
				continue
			# At long-distance LOD the terrain and road are both visual-only. Use
			# the centreline datum so cross-slope cannot lift the entire ribbon;
			# detailed shoulder cuts are created when this region becomes local.
			var required: float = terrain.height_at(point_2d.x, point_2d.y) + 0.15
			heights.append(required)
		# This continuation is visual-only. Limit bridge influence to a local
		# run: a crater lip may carry the deck across its nearby hollow, but it
		# must never lift the remaining tens of kilometres of road.
		heights = _bridge_local_hollows(heights, points2d)
		var previous := Vector3(points2d[0].x, heights[0], points2d[0].y)
		for i in range(1, heights.size()):
			var current := Vector3(points2d[i].x, heights[i], points2d[i].y)
			var tangent := (current - previous).normalized()
			var right := tangent.cross(Vector3.UP).normalized()
			segments.append({"index": i - 1, "a": previous, "b": current, "ra": right, "rb": right, "na": Vector3.UP, "nb": Vector3.UP, "position": (previous + current) * 0.5, "route": route.id, "paint": false, "rails": true, "half_width": half_width, "clearance": current.y - terrain.height_at(current.x, current.z), "support_stride": 1})
			previous = current
		if not segments.is_empty():
			var clearances: Array[float] = []
			for segment: Dictionary in segments:
				clearances.append(float(segment.clearance))
			clearances.sort()
			far_grounding_by_route[route.id] = {
				"segments": segments.size(),
				"median_clearance": clearances[clearances.size() / 2],
				"max_clearance": clearances.back(),
			}
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
	var switchbacks := _switchback_waypoints(start, goal)
	if not switchbacks.is_empty():
		return switchbacks
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

func _switchback_waypoints(start: Vector2, goal: Vector2) -> Array[Vector2]:
	var direct_distance := start.distance_to(goal)
	if direct_distance < 1.0:
		return []
	var rise := absf(terrain.height_at(goal.x, goal.y) - terrain.height_at(start.x, start.y))
	if rise / direct_distance <= SWITCHBACK_TRIGGER_GRADE:
		return []
	var required_length := rise / SWITCHBACK_TARGET_GRADE
	var direction := (goal - start) / direct_distance
	var side := Vector2(-direction.y, direction.x)
	var lead := minf(SWITCHBACK_LEAD, direct_distance * 0.2)
	var inner_start := start + direction * lead
	var inner_distance := direct_distance - lead * 2.0
	# Use the fewest broad traverses that provide enough climbing distance.
	# Odd leg counts put the final traverse on the opposite side of the first,
	# making the alignment balanced around its strategic centreline.
	var leg_count := 3
	while leg_count < SWITCHBACK_MAX_LEGS and lead * 2.0 + _switchback_length(inner_distance, SWITCHBACK_OFFSET, leg_count) < required_length * SWITCHBACK_ROUNDING_ALLOWANCE:
		leg_count += 2
	var result: Array[Vector2] = [inner_start]
	for i in range(1, leg_count):
		var along := inner_distance * float(i) / float(leg_count)
		var sign_value := 1.0 if i % 2 == 1 else -1.0
		result.append(inner_start + direction * along + side * SWITCHBACK_OFFSET * sign_value)
	result.append(goal - direction * lead)
	result.append(goal)
	return result

func _register_main_road_cuts() -> void:
	if not terrain.has_method("add_road_cut"):
		return
	for segments: Array in descriptors_by_tile.values():
		for segment: Dictionary in segments:
			terrain.add_road_cut(segment.a, segment.b, lane_width + 0.4)
	if terrain.has_method("refresh_road_grading"):
		terrain.refresh_road_grading()

func _switchback_length(direct_distance: float, offset: float, leg_count: int) -> float:
	var along := direct_distance / float(leg_count)
	if leg_count <= 1:
		return direct_distance
	return 2.0 * Vector2(along, offset).length() + float(leg_count - 2) * Vector2(along, offset * 2.0).length()

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
		var required := 0.0
		# Fit to the mean cross-section. The terrain pass cuts the uphill shoulder
		# down to the deck; using the highest edge as the whole profile's datum
		# made every road on a side slope float above its centreline.
		for across in range(-8, 9):
			var p := samples[i] + right * (lane_width + 0.4) * float(across) / 8.0
			required += terrain.height_at(p.x, p.z) + surface_offset
		required /= 17.0
		# Near a pinned colony pad, blend the road down onto the pad level so the
		# spur arrives at town level instead of on a viaduct.
		if not ground_pin.is_empty():
			var d: float = Vector2(samples[i].x, samples[i].z).distance_to(ground_pin.center)
			var blend := smoothstep(ground_pin.radius * 0.5, ground_pin.radius, d)
			required = lerpf(ground_pin.level + surface_offset, required, blend)
		heights.append(required)
	# Fit the road around the natural surface instead of treating every crest as
	# an inviolable floor. High spots become shallow cuttings, low spots become
	# short supported spans, and broad elevation changes are handled by the
	# switchback alignment above.
	heights = _fit_ground_profile(heights, samples)
	for i in samples.size():
		# A former smoothing pass restored clearance by adding its single worst
		# error to every sample, lifting kilometres of otherwise flat road because
		# of one remote bump. The fitted cut/fill profile needs no global lift.
		samples[i].y = heights[i]
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

func _fit_ground_profile(required: PackedFloat32Array, samples: PackedVector3Array) -> PackedFloat32Array:
	# Each directional pass is independently grade-safe. Their average is also
	# grade-safe (the constraint is convex), while cancelling the tendency of a
	# one-way pass to drag a remote crest or hollow through the entire route.
	var forward := required.duplicate()
	for i in range(1, forward.size()):
		var limit := MAX_GRADE * samples[i].distance_to(samples[i - 1])
		forward[i] = clampf(required[i], forward[i - 1] - limit, forward[i - 1] + limit)
	var backward := required.duplicate()
	for i in range(backward.size() - 2, -1, -1):
		var limit := MAX_GRADE * samples[i].distance_to(samples[i + 1])
		backward[i] = clampf(required[i], backward[i + 1] - limit, backward[i + 1] + limit)
	# Pick one global blend for the whole route. Every such blend remains
	# grade-safe; minimizing the median absolute earthwork keeps most stations
	# on grade while allowing balanced local cuts and supported fills.
	var forward_weight := 0.5
	var best_median_error := INF
	for candidate_index in 41:
		var candidate := float(candidate_index) / 40.0
		var errors: Array[float] = []
		for i in required.size():
			errors.append(absf(lerpf(backward[i], forward[i], candidate) - required[i]))
		errors.sort()
		var median_error: float = errors[errors.size() / 2]
		if median_error < best_median_error:
			best_median_error = median_error
			forward_weight = candidate
	var profile := PackedFloat32Array()
	profile.resize(required.size())
	for i in required.size():
		profile[i] = lerpf(backward[i], forward[i], forward_weight)
	return profile

func _bridge_local_hollows(required: PackedFloat32Array, points: Array[Vector2]) -> PackedFloat32Array:
	var profile := required.duplicate()
	# Only bridge a point when there are compatible ground anchors on both
	# sides. A one-sided peak is a slope to follow (with switchbacks), not a
	# reason to project a viaduct hundreds of metres into the distance.
	var radius_limit := maxi(1, ceili(BRIDGE_MAX_RUN / FAR_LOD_STEP))
	for i in range(1, required.size() - 1):
		for radius in range(1, radius_limit + 1):
			var left := i - radius
			var right := i + radius
			if left < 0 or right >= required.size():
				break
			var span := points[left].distance_to(points[right])
			if span > BRIDGE_MAX_RUN * 2.0:
				break
			if absf(required[right] - required[left]) / maxf(0.01, span) > MAX_GRADE:
				continue
			var t := points[left].distance_to(points[i]) / maxf(0.01, span)
			profile[i] = maxf(profile[i], lerpf(required[left], required[right], t))
	return profile

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
