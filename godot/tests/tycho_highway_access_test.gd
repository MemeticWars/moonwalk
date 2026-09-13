extends SceneTree

const Roads := preload("res://scripts/road_streamer.gd")
const TychoSite := preload("res://scripts/tycho_site.gd")
const DIRECTION := Vector2(0.2239, -0.9746)
var failures := 0

class TerrainStub extends Node:
	var center := Vector2i.ZERO
	var city_level := 0.0
	func height_at(x: float, z: float) -> float:
		return 0.02 * x - 0.01 * z

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := TerrainStub.new()
	root.add_child(terrain)
	var roads := Roads.new()
	roads.terrain = terrain
	roads.active_colony = "Tycho Station"
	root.add_child(roads)
	await physics_frame
	var highway: Array = []
	for segments: Array in roads.descriptors_by_tile.values():
		for segment: Dictionary in segments:
			if segment.route == "InPost Central--Tycho Station":
				highway.append(segment)
	check(not highway.is_empty(), "Tycho must have its InPost highway")
	var nearest_gate := INF
	var rail_free := false
	# Same GATE_DIR/anchor relationship tycho_city.gd and road_streamer.gd
	# actually build, so this test tracks any future relocation of the site.
	var gate := TychoSite.CENTER + Vector2(0.0, -100.0)
	var origin := TychoSite.CENTER + TychoSite.HIGHWAY_ANCHOR_OFFSET
	var junction := origin + DIRECTION * 175.0
	for segment: Dictionary in highway:
		var a := Vector2(segment.a.x, segment.a.z)
		var b := Vector2(segment.b.x, segment.b.z)
		var t := clampf((gate - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
		nearest_gate = minf(nearest_gate, gate.distance_to(a.lerp(b, t)))
		if Vector2(segment.position.x, segment.position.z).distance_to(junction) < 25.0 and not segment.get("rails", true):
			rail_free = true
	check(nearest_gate > 60.0, "Main motorway must stay clear of the Tycho airlock")
	check(rail_free, "City and cosmoport junction must have no motorway rail")
	var far_lod := roads.get_node("FarHighwayLOD")
	var far_deck_found := false
	for child in far_lod.get_children():
		if String(child.name).begins_with("FarDeck_"):
			far_deck_found = true
	check(far_deck_found, "Tycho keeps a visible long-distance highway LOD")
	check(far_lod.get_child_count() >= 2, "Far LOD must also carry batched rails (and piers, where clearance runs high)")
	print("TYCHO HIGHWAY ACCESS TEST: ", failures, " failures; gate clearance=", nearest_gate)
	quit(1 if failures else 0)
