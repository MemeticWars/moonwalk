extends SceneTree
const Lamps := preload("res://scripts/highway_lamps.gd")
const Roads := preload("res://scripts/road_streamer.gd")
var failures := 0

class Ground extends Node:
	func height_at(_x: float, _z: float) -> float:
		return 0.0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var ground := Ground.new()
	var road := Roads.new()
	road.terrain = ground
	road.lane_width = 2.0 * preload("res://scripts/lunar_lorry.gd").highway_vehicle_width()
	road._bake_route("test", [Vector2(-180, 0), Vector2(220, 0)], 0.2)
	var layout := Lamps.layout(road.descriptors_by_tile, road.lane_width + 0.4)
	check(layout == Lamps.layout(road.descriptors_by_tile, road.lane_width + 0.4), "Deterministic lamp layout")
	var lamps: Array = []
	for tile in layout.values():
		lamps.append_array(tile)
	check(lamps.size() == 20, "Both sides illuminated along the entire 400 m route")
	for side: float in [-1.0, 1.0]:
		var selected := lamps.filter(func(lamp: Dictionary) -> bool: return lamp.side == side)
		selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.station < b.station)
		for i in selected.size():
			var lamp: Dictionary = selected[i]
			if i > 0:
				check(is_equal_approx(lamp.station - selected[i - 1].station, 40.0), "40 m spacing across tile boundaries")
			var inward: Vector3 = (lamp.centre - lamp.transform.origin).normalized()
			check(lamp.transform.basis.x.dot(inward) > 0.999, "Lamp arm faces the road")
			check(lamp.transform.origin.distance_to(lamp.centre) > road.lane_width, "Pole leaves lane width clear")
	var near := Lamps.build(lamps, true)
	var far := Lamps.build(lamps, false)
	var light_count := 0
	for child in near.get_children():
		if child is SpotLight3D:
			light_count += 1
			check((-child.basis.z).dot(Vector3.DOWN) > 0.999, "Lights shine down")
			check(child.spot_range >= Lamps.HEIGHT and child.light_energy > 0.0, "Lights reach the deck")
	check(light_count == lamps.size(), "Every nearby fixture has a real light")
	check(far.get_child_count() == 3, "Distant fixtures use only three batched meshes")
	check(Lamps.shared_mesh.get_aabb().end.x > 3.0 and Lamps.light_position().x > 2.0, "Actual imported arm and light extend inward along +X")
	check(absf(Lamps.shared_mesh.get_aabb().size.y - 12.0) < 0.05, "Imported lamp height is 12 m")
	check(Lamps.shared_mesh.get_faces().size() / 3 < 5000, "Lamp uses the reduced source asset")
	print("LAMP TEST: %d failures; %d fixtures; %d triangles per shared source mesh" % [failures, lamps.size(), Lamps.shared_mesh.get_faces().size() / 3])
	near.free()
	far.free()
	road.free()
	ground.free()
	quit(1 if failures else 0)
