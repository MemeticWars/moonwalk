extends RefCounted
## Shared, deterministic excavation in world XZ metres. No scene dependencies.
const Site := preload("res://scripts/tycho_site.gd")
const POND1_CENTER := Site.CENTER + Vector2(-18, -4)
const POND1_RADII := Vector2(4.5, 3.2)
const POND2_CENTER := Site.CENTER + Vector2(-170, 0)
const POND2_RADII := Vector2(32, 18)
const POND1_DEPTH := 1.0
const POND2_DEPTH := 1.5
const STREAM_DEPTH := 0.5
const STREAM_WIDTH := 0.5
const TUNNEL_STREAM_Z := 2.5
const WALKWAY_CENTER := Site.CENTER + Vector2(-114.5, 0.8)
const WALKWAY_SIZE := Vector2(41.0, 2.4)
const CELL := 2.0
const STREAM_STEP := 0.0625
const POND_STEP := 0.5
## Westward beside the park's cross-avenue, between the twin houses at
## z=0/-22, between tanks at z=-4/-16, then through the west airlock.
const CONTROLS: Array[Vector2] = [
	Vector2(-18, -4), Vector2(-24, -5), Vector2(-27, -11),
	Vector2(-39, -11), Vector2(-60, -11), Vector2(-83, -11),
	Vector2(-93, -2), Vector2(-97, TUNNEL_STREAM_Z), Vector2(-120, TUNNEL_STREAM_Z),
	Vector2(-138, TUNNEL_STREAM_Z), Vector2(-148, 0),
]
static var _route := PackedVector2Array()
static var _segments_by_cell: Dictionary = {}

static func route() -> PackedVector2Array:
	if not _route.is_empty():
		return _route
	# Quadratic corner rounding stays inside the control polygon, unlike an
	# interpolating spline which can overshoot into buildings in narrow gaps.
	var anchors := PackedVector2Array([CONTROLS[0]])
	for i in range(1, CONTROLS.size() - 1):
		var corner := CONTROLS[i]
		var radius := minf(3.0, minf(corner.distance_to(CONTROLS[i-1]), corner.distance_to(CONTROLS[i+1])) * 0.35)
		var a := corner.move_toward(CONTROLS[i-1], radius)
		var b := corner.move_toward(CONTROLS[i+1], radius)
		anchors.append(a)
		for j in range(1, 17):
			var t := j / 16.0
			anchors.append(a.lerp(corner, t).lerp(corner.lerp(b, t), t))
	anchors.append(CONTROLS[-1])
	_route.append(Site.CENTER + anchors[0])
	for i in range(1, anchors.size()):
		var n := maxi(1, ceili(anchors[i-1].distance_to(anchors[i]) / 0.25))
		for j in range(1, n+1):
			_route.append(Site.CENTER + anchors[i-1].lerp(anchors[i], float(j)/n))
	for i in range(_route.size()-1):
		var lo := _route[i].min(_route[i+1]) - Vector2.ONE * 0.9
		var hi := _route[i].max(_route[i+1]) + Vector2.ONE * 0.9
		for z in range(floori(lo.y/CELL), floori(hi.y/CELL)+1):
			for x in range(floori(lo.x/CELL), floori(hi.x/CELL)+1):
				var key := Vector2i(x,z)
				if not _segments_by_cell.has(key):
					_segments_by_cell[key] = []
				_segments_by_cell[key].append(i)
	return _route

static func cell_step(point: Vector2) -> float:
	route()
	var key := Vector2i(floori(point.x/CELL), floori(point.y/CELL))
	if _segments_by_cell.has(key):
		return STREAM_STEP
	var center := (Vector2(key) + Vector2.ONE * 0.5) * CELL
	for pond in [[POND1_CENTER, POND1_RADII], [POND2_CENTER, POND2_RADII]]:
		if ((center - pond[0]) / (pond[1] + Vector2.ONE * CELL)).length() <= 1.0:
			return POND_STEP
	return CELL

static func depth(point: Vector2) -> float:
	var result := 0.0
	for pond in [[POND1_CENTER, POND1_RADII, POND1_DEPTH], [POND2_CENTER, POND2_RADII, POND2_DEPTH]]:
		var radius: float = ((point - pond[0]) / pond[1]).length()
		# Broad bottom with smoothly rounded, continuous banks.
		result = maxf(result, pond[2] * (1.0 - smoothstep(0.30, 1.0, radius)))
	var r := stream_distance(point) / (STREAM_WIDTH * 0.5)
	if r < 1.0:
		# Half-ellipse: rounded U, 50 cm wide at grade, 50 cm deep.
		result = maxf(result, STREAM_DEPTH * sqrt(maxf(0.0, 1.0-r*r)))
	return result

static func stream_distance(point: Vector2) -> float:
	route()
	var key := Vector2i(floori(point.x/CELL), floori(point.y/CELL))
	var result := INF
	for i: int in _segments_by_cell.get(key, []):
		var closest := Geometry2D.get_closest_point_to_segment(point, _route[i], _route[i+1])
		result = minf(result, point.distance_to(closest))
	return result

static func bed_height(point: Vector2, grade: float) -> float:
	return grade - depth(point)

static func west_passage_weight(point: Vector2) -> float:
	# The blended dome pads leave a raised DEM ridge in their 20 m gap.
	# Grade the existing passage and its banks before excavating the brook.
	var p := point - Site.CENTER
	return smoothstep(-143.0,-137.0,p.x) * (1.0-smoothstep(-93.0,-87.0,p.x)) * (1.0-smoothstep(3.6,6.0,absf(p.y)))
