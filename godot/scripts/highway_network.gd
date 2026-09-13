extends RefCounted
## All unordered colony pairs, measured along the lunar surface.
const RADIUS_KM := 1737.4
const LIMIT_KM := 700.0
## Explicit requested regional network, exempt from the proximity threshold.
const FARSIDE_LOCATIONS := ["Chang'e Relay", "Blooming Flower", "Daedalus Port"]
const ROUTE_SAMPLE_KM := 10.0

static func is_farside_connection(a: Dictionary, b: Dictionary) -> bool:
	return a.name in FARSIDE_LOCATIONS and b.name in FARSIDE_LOCATIONS and a.name != b.name

static func unit(location: Dictionary) -> Vector3:
	var lat := deg_to_rad(float(location.latitude))
	var lon := deg_to_rad(float(location.longitude))
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))

static func distance_km(a: Dictionary, b: Dictionary) -> float:
	# Scalar floats retain double precision; Vector3 components are float32.
	var lat_a := deg_to_rad(float(a.latitude))
	var lat_b := deg_to_rad(float(b.latitude))
	var dlat := lat_b - lat_a
	var dlon := deg_to_rad(float(b.longitude) - float(a.longitude))
	var hav := pow(sin(dlat * 0.5), 2) + cos(lat_a) * cos(lat_b) * pow(sin(dlon * 0.5), 2)
	var distance := RADIUS_KM * 2.0 * asin(sqrt(clampf(hav, 0.0, 1.0)))
	# Micrometre precision makes exactly 700 km stable at the strict boundary.
	return snappedf(distance, 0.000000001)

static func route_points(a: Dictionary, b: Dictionary, spacing_km: float = ROUTE_SAMPLE_KM) -> Array[Dictionary]:
	# Canonical centreline for the whole road, not merely the first local spur.
	# Each active terrain sector can request a short portion of this path.
	var distance := distance_km(a, b)
	var count := maxi(1, ceili(distance / spacing_km))
	var start := unit(a)
	var end := unit(b)
	var points: Array[Dictionary] = []
	for i in range(count + 1):
		var direction := start.slerp(end, float(i) / float(count)).normalized()
		points.append({"latitude": rad_to_deg(asin(direction.y)), "longitude": rad_to_deg(atan2(direction.x, direction.z)), "station_km": distance * float(i) / float(count)})
	return points

static func build(locations: Array) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	for i in locations.size():
		for j in range(i + 1, locations.size()):
			var a: Dictionary = locations[i]
			var b: Dictionary = locations[j]
			var distance := distance_km(a, b)
			var farside := is_farside_connection(a, b)
			if distance > 0.0 and (distance < LIMIT_KM or farside):
				routes.append({"id": "%s--%s" % [a.name, b.name], "from": a.name,
					"to": b.name, "distance_km": distance, "a": a, "b": b,
					"connection_rule": "farside_region" if farside else "proximity",
					"points": route_points(a, b)})
	return routes
