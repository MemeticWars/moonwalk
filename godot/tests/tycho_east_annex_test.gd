extends SceneTree

const City := preload("res://scripts/tycho_city.gd")
const Layout := preload("res://scripts/tycho_water_layout.gd")

class FlatTerrain extends "res://scripts/lunar_terrain.gd":
	func _ready() -> void:
		city_enabled = true
		city_level = 10.0
	func _process(_delta: float) -> void:
		pass
	func natural_height(_x: float, _z: float) -> float:
		return 10.0
	func elevation(_latitude: float, _longitude: float) -> float:
		return 10.0
	func latlon_at(_x: float, _z: float) -> Vector2:
		return Vector2.ZERO
	func survey_weight(_x: float, _z: float) -> float:
		return 1.0
	func _build_rocks(_root: Node3D, _key: Vector2i) -> void:
		pass

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := FlatTerrain.new()
	root.add_child(terrain)
	var annex := preload("res://scripts/tycho_east_annex.gd").new()
	annex.terrain = terrain
	root.add_child(annex)
	annex.set_process(false)
	annex._build()
	await process_frame
	var counts := {}
	for descriptor: Dictionary in annex.habitat_descriptors:
		var key := "%s/%s" % [descriptor.site, descriptor.kind]
		counts[key] = int(counts.get(key, 0)) + 1
	check(counts.get("D2/block-of-flats", 0) == 7, "D2 must contain exactly seven apartment towers")
	check(counts.get("D2/twin-houses", 0) == 4 and counts.get("D2/l-shape-building", 0) == 2,
		"D2 must mix towers with twin and L-shaped homes")
	check(counts.get("D2/park-birch", 0) == 8 and counts.get("D2/park-pine", 0) == 8 and counts.get("D2/park-beech", 0) == 0,
		"D2 park must mix birches and pines without beeches")
	check(counts.get("m1/greenhouse", 0) == 9 and counts.get("m1/twin-houses", 0) == 1 and counts.get("m1/l-shape-building", 0) == 1,
		"m1 must be a dense nine-greenhouse quarter with small homes")
	check(counts.get("m2/twin-houses", 0) == 2 and counts.get("m2/l-shape-building", 0) == 1,
		"m2 must contain twin and L-shaped homes")
	check(counts.get("m3/twin-houses", 0) == 2 and counts.get("m3/l-shape-building", 0) == 1,
		"Lake dome m3 must retain only three small homes")
	for descriptor: Dictionary in annex.habitat_descriptors:
		if descriptor.site != "m3":
			continue
		var size: Array = annex.dimensions[descriptor.kind].size_m
		for x in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var corner := Vector2(float(size[0]) * x, float(size[2]) * z).rotated(float(descriptor.yaw)) + Vector2(descriptor.point)
				var pond_coordinate := (corner - Layout.POND2_CENTER) / Layout.POND2_RADII
				check(pond_coordinate.length() > 1.0, "m3 homes must remain outside the lake")
	var d1 := City.new()
	d1.dimensions = annex.dimensions
	d1._layout()
	var d1_species := {}
	for descriptor: Dictionary in d1.descriptors:
		if String(descriptor.kind).begins_with("park-"):
			d1_species[descriptor.kind] = int(d1_species.get(descriptor.kind, 0)) + 1
	check(d1_species.get("park-beech", 0) == 18 and d1_species.get("park-birch", 0) == 18 and d1_species.get("park-pine", 0) == 0,
		"D1 must retain only beeches and birches")
	d1.free()
	for site_name in ["D2", "m1", "m2", "m3"]:
		check(annex.has_node("Lawn_" + site_name), site_name + " must have green ground cover")
		check(annex.has_node("Grass_" + site_name), site_name + " must have blade grass")
	var centres := [City.D2_CENTER, City.M1_CENTER, City.M2_CENTER, City.M3_CENTER]
	for centre: Vector2 in centres:
		var reached := false
		for segment: PackedVector2Array in annex.pedestrian_segments:
			if annex._distance_to_segment(centre, segment[0], segment[1]) < 0.01:
				reached = true
				break
		check(reached, "Pedestrian network must reach sphere centre " + str(centre))
	var m3_grass: Node3D = annex.get_node("Grass_m3")
	var m3_instances := m3_grass.get_child(0) as MultiMeshInstance3D
	var m3_buffer: PackedFloat32Array = m3_instances.multimesh.buffer
	var sampled_clear := true
	var blocked_sample := Vector2.ZERO
	for i in range(0, m3_instances.multimesh.instance_count, 97):
		var local := Vector2(m3_buffer[i * 16 + 3], m3_buffer[i * 16 + 11])
		if Layout.depth(City.M3_CENTER + local) > 0.02:
			sampled_clear = false
			blocked_sample = City.M3_CENTER + local
			break
	check(sampled_clear, "m3 grass must stay out of the excavated lake; sample " + str(blocked_sample))
	print("TYCHO EAST ANNEX: %d failures; %d placed habitat/park modules" % [failures, annex.habitat_descriptors.size()])
	quit(1 if failures else 0)
