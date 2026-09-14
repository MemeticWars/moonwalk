extends SceneTree

const SunHorizon := preload("res://scripts/sun_horizon.gd")

class FakeTerrain extends RefCounted:
	var base_elevation := 0.0
	var ridge_lat := INF
	var ridge_height := 0.0
	func latlon_at(_x: float, _z: float) -> Vector2:
		return Vector2.ZERO
	func elevation(lat: float, _lon: float) -> float:
		return ridge_height if absf(lat - ridge_lat) < 0.5 else 0.0

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := FakeTerrain.new()
	var pos := Vector3.ZERO

	check(SunHorizon.is_visible(terrain, pos, Vector3(0, 0, 1)), "Sun straight overhead on flat ground must be visible")
	check(SunHorizon.is_visible(terrain, pos, _sun(1.0)), "Sun 1 deg above a flat horizon must be visible")
	check(not SunHorizon.is_visible(terrain, pos, _sun(-1.0)), "Sun 1 deg below a flat horizon must be occluded (night)")

	# A ridge the observer's own local tiles never load (50 km out along the
	# sun's meridian), tall enough to poke above a grazing 1 deg sun.
	terrain.ridge_lat = 1.646
	terrain.ridge_height = 5000.0
	check(not SunHorizon.is_visible(terrain, pos, _sun(1.0)), "A distant ridge on the sun's own azimuth must block it")

	# Same ridge height, but off to the side of the sun's path -- must not matter.
	terrain.ridge_lat = 45.0
	check(SunHorizon.is_visible(terrain, pos, _sun(1.0)), "A ridge far off the sun's azimuth must not block it")

	if failures == 0:
		print("sun_horizon_test: all checks passed")
	quit(1 if failures > 0 else 0)

func _sun(elevation_deg: float) -> Vector3:
	var eps := deg_to_rad(elevation_deg)
	return Vector3(0, cos(eps), sin(eps))
