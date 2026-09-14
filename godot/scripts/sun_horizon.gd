extends RefCounted
## Whole-Moon sun visibility: is the sun geometrically above the horizon at a
## given surface point, or blocked by a crater rim/mountain range that may lie
## far beyond the locally streamed terrain? This is independent of the
## shadow map, which only resolves occlusion by geometry already loaded
## around the camera.
##
## Works by marching a straight ray (the sun is effectively at infinite
## distance, so its rays are parallel) from the observer through the Moon's
## body-fixed Cartesian frame, and comparing the ray's distance from the
## Moon's centre against the real elevation() at the lat/lon it passes over.

const RADIUS_M := 1737400.0
## Generous upper bound on any lunar relief (the tallest known peaks are
## ~10.8 km, near Leibnitz beta at the south pole) -- used only to bound how
## far the march needs to go, not as a physical limit.
const MAX_RELIEF_M := 15000.0
const MAX_RANGE_M := 400000.0
const FIRST_STEP_M := 250.0
const STEP_GROWTH := 1.4

## terrain: any object exposing elevation(lat, lon), latlon_at(x, z) and
## base_elevation, e.g. LunarTerrain. world_pos: local tangent-plane metres,
## same frame as theia.position. sun_direction: unit vector from the Moon's
## centre toward the sun, in the same body-fixed frame as moon_globe.gd's
## geo(lat, lon) (i.e. moonwalk.gd's planet_sun_direction).
static func is_visible(terrain: Object, world_pos: Vector3, sun_direction: Vector3) -> bool:
	var sun := sun_direction.normalized()
	var latlon: Vector2 = terrain.latlon_at(world_pos.x, world_pos.z)
	var origin := _cartesian(latlon.x, latlon.y, terrain.base_elevation + world_pos.y)
	var sin_elevation := origin.normalized().dot(sun)
	# Farthest distance at which even the tallest plausible relief could still
	# poke above the ray: the largest root of
	# |origin + t*sun|^2 <= (RADIUS_M + MAX_RELIEF_M)^2.
	var b := RADIUS_M * sin_elevation
	var c := 2.0 * RADIUS_M * MAX_RELIEF_M + MAX_RELIEF_M * MAX_RELIEF_M
	var t_max := minf(-b + sqrt(b * b + c), MAX_RANGE_M)
	var t := FIRST_STEP_M
	var step := FIRST_STEP_M
	while t <= t_max:
		var point: Vector3 = origin + sun * t
		var radius := point.length()
		var lat := rad_to_deg(asin(clampf(point.y / radius, -1.0, 1.0)))
		var lon := rad_to_deg(atan2(point.x, point.z))
		if radius <= RADIUS_M + terrain.elevation(lat, lon):
			return false
		t += step
		step *= STEP_GROWTH
	return true

static func _cartesian(lat_deg: float, lon_deg: float, elevation_m: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)) * (RADIUS_M + elevation_m)
