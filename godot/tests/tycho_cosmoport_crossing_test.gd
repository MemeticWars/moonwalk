extends SceneTree
## The cosmoport's access road and off-ramp both meet the main highway at its
## rail-free opening (station 175 along the baked carriageway). All three
## decks must sit at the same height there, or the crossing shows a visible
## bulge/step and an exposed collision edge -- see tycho_cosmoport.gd's
## HIGHWAY_DECK_OFFSET_M.

const Roads := preload("res://scripts/road_streamer.gd")
const Cosmoport := preload("res://scripts/tycho_cosmoport.gd")
const TychoSite := preload("res://scripts/tycho_site.gd")
const GATE_DIR := Vector2(0.0, -1.0)
const HIGHWAY_DIR := Vector2(0.2239, -0.9746)
var failures := 0

class TerrainStub extends Node3D:
	var center := Vector2i.ZERO
	var city_level := 0.0
	func height_at(_x: float, _z: float) -> float:
		return city_level
	func add_city_pad(_c: Vector2, _r: float, _blend: float, _extra: float, _level: float) -> void:
		pass

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
	roads.build_interchanges = false
	root.add_child(roads)
	await physics_frame

	var origin: Vector2 = TychoSite.CENTER + TychoSite.HIGHWAY_ANCHOR_OFFSET
	var hwy := HIGHWAY_DIR.normalized()
	var junction: Vector2 = origin + hwy * 175.0

	# Highway's own baked height at the crossing.
	var highway_y := INF
	var nearest := INF
	for segments: Array in roads.descriptors_by_tile.values():
		for segment: Dictionary in segments:
			if segment.route != "InPost Central--Tycho Station":
				continue
			var mid := Vector2(segment.position.x, segment.position.z)
			var d := mid.distance_to(junction)
			if d < nearest:
				nearest = d
				highway_y = segment.position.y
	check(nearest < 10.0, "A highway segment must sample right at the rail-free junction")
	check(absf(highway_y - (terrain.city_level + Cosmoport.HIGHWAY_DECK_OFFSET_M)) < 0.02,
		"Highway deck height at the junction must match HIGHWAY_DECK_OFFSET_M (got %.3f, expected %.3f)"
		% [highway_y, terrain.city_level + Cosmoport.HIGHWAY_DECK_OFFSET_M])

	var cosmoport := Cosmoport.new()
	cosmoport.terrain = terrain
	cosmoport.gate_dir = GATE_DIR
	cosmoport.highway_dir = HIGHWAY_DIR
	cosmoport.highway_origin = TychoSite.HIGHWAY_ANCHOR_OFFSET
	cosmoport.position = Vector3(TychoSite.CENTER.x, terrain.city_level, TychoSite.CENTER.y)
	cosmoport.test_mode = true
	root.add_child(cosmoport)
	await physics_frame

	# Any local-road ribbon segment whose centre lands near the crossing
	# (access road's last few segments, the off-ramp's first few) must be
	# level with the highway there.
	# `junction` is already in the same absolute (CENTER-relative) frame as
	# cosmoport.position -- see tycho_city.gd's gate_cluster, which adds
	# Site.CENTER once, not once per node. Do not add cosmoport.position.x/z
	# again here.
	var crossing_world := Vector3(junction.x, cosmoport.position.y, junction.y)
	var checked := 0
	for child in cosmoport.get_children():
		if not child is MeshInstance3D:
			continue
		var mi := child as MeshInstance3D
		if not (mi.mesh is BoxMesh):
			continue
		var flat := Vector2(mi.global_position.x, mi.global_position.z)
		if flat.distance_to(Vector2(crossing_world.x, crossing_world.z)) > 10.0:
			continue
		# _ribbon() centres each segment 0.08 m below the deck surface it
		# represents (see tycho_cosmoport.gd::_ribbon).
		var deck_y := mi.global_position.y + 0.08
		checked += 1
		check(absf(deck_y - highway_y) < 0.05,
			"Local road deck near the crossing must be level with the highway (got %.3f, highway %.3f)" % [deck_y, highway_y])
	check(checked >= 2, "Expected both the access road and the off-ramp to have a segment near the crossing")
	print("TYCHO COSMOPORT CROSSING TEST: ", failures, " failures; highway_y=", snappedf(highway_y, 0.001), " segments_checked=", checked)
	quit(1 if failures else 0)
