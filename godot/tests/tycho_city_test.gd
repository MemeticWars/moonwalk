extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := preload("res://scripts/lunar_terrain.gd").new()
	terrain.colony = {"name": "Tycho Station", "latitude": -43.66, "longitude": -11.3}
	root.add_child(terrain)
	var city := preload("res://scripts/tycho_city.gd").new()
	city.terrain = terrain
	root.add_child(city)
	var deadline := Time.get_ticks_msec() + 60000
	while city.loaded.size() != city.descriptors.size() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(city.loaded.size() == city.descriptors.size(), "Every nearby city module must finish streaming")
	check(city.descriptors.size() == 69, "C-shaped city: buildings, two road benches and 36 trees")
	var bench_count := 0
	var greenhouse_count := 0
	var greenhouse_film_count := 0
	var west_trees := 0
	var east_trees := 0
	var species := {}
	var beech_bark_silvers := {}
	var beech_leaf_greens := {}
	var birch_greens := {}
	var pine_count := 0
	var tree_scales := PackedFloat32Array()
	for descriptor: Dictionary in city.descriptors:
		if descriptor.kind == "greenhouse":
			greenhouse_count += 1
		if descriptor.kind == "bench":
			bench_count += 1
		if String(descriptor.kind).begins_with("park-"):
			west_trees += 1 if descriptor.point.x < city.Site.CENTER.x else 0
			east_trees += 1 if descriptor.point.x >= city.Site.CENTER.x else 0
			species[descriptor.kind] = int(species.get(descriptor.kind, 0)) + 1
			if descriptor.has("beech_bark_silver"):
				beech_bark_silvers[descriptor.beech_bark_silver.to_html()] = true
				beech_leaf_greens[descriptor.beech_leaf_green.to_html()] = true
			if descriptor.kind == "park-pine":
				pine_count += 1
			tree_scales.append(float(descriptor.get("tree_scale", 1.0)))
			if descriptor.has("foliage_tint"):
				birch_greens[descriptor.foliage_tint.to_html()] = true
	check(west_trees == 36 and east_trees == 0, "Trees must form one west garden and leave the east lawn for glasshouses")
	check(greenhouse_count == 3, "Three greenhouses must occupy the eastern agricultural quarter")
	check(bench_count == 2, "Two benches must line the main road")
	var seated_agnes_count := 0
	for index in city.loaded:
		var resident := city.loaded[index].get_node_or_null("SeatedAgnes") as Node3D
		if resident != null:
			seated_agnes_count += 1
			check(resident.scale.is_equal_approx(Vector3.ONE),
				"Seated Agnes must use the fitted bench scale")
			var expected_seat_y: float = 0.49038946628570557 * city.BENCH_HEIGHT_SCALE + 0.005 + city.SEATED_AGNES_LIFT
			check(absf(resident.position.y - expected_seat_y) < 0.001,
				"Seated Agnes must follow the lowered bench seat")
			var book := resident.get_node_or_null("VoyagesExtraordinaires") as Node3D
			check(book != null and absf(book.position.y - 0.26) < 0.001 and absf(book.position.z - 0.30) < 0.001 and
				book.scale.is_equal_approx(Vector3.ONE * city.BOOK_SCALE),
				"Voyages Extraordinaires must be 1.5x larger and rest on Agnes's lap")
	check(seated_agnes_count == 1, "Exactly one bench must have seated Agnes")
	var greenhouse_z := []
	for descriptor: Dictionary in city.descriptors:
		if descriptor.kind == "greenhouse":
			check(absf(descriptor.point.x - (city.Site.CENTER.x + 23.0)) < 0.01, "Greenhouses must sit close to the west park edge")
			greenhouse_z.append(descriptor.point.y)
	greenhouse_z.sort()
	check(greenhouse_z.size() == 3 and absf(greenhouse_z[1] - greenhouse_z[0] - 8.0) < 0.01 and absf(greenhouse_z[2] - greenhouse_z[1] - 8.0) < 0.01,
		"Greenhouses must form a compact 8 m spaced row")
	for i in city.loaded:
		if city.descriptors[i].kind == "greenhouse":
			var film: MeshInstance3D = city.loaded[i].get_node("TransparentFilm")
			var film_material := film.mesh.surface_get_material(0) as StandardMaterial3D
			check(film_material != null and film_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
				"Every greenhouse must have a transparent film shell")
			greenhouse_film_count += 1
	check(greenhouse_film_count == 3, "Three greenhouse film shells must be present")
	check(absf(float(city.dimensions["greenhouse"].size_m[0]) - 12.0) < 0.01 and absf(float(city.dimensions["greenhouse"].size_m[1]) - 8.0 / 3.0) < 0.01,
		"Greenhouse width must be halved while height stays reduced threefold")
	check(absf(float(city.dimensions["tomatoes"].size_m[1]) - float(city.dimensions["tomato"].size_m[1])) < 0.001,
		"Tomato cluster height must match the single tomato height")
	check(absf(float(city.dimensions["tomatoes"].size_m[0]) / 1.9001309871673584 - float(city.dimensions["tomatoes"].size_m[1]) / 0.5560800433158875) < 0.001 and
		absf(float(city.dimensions["tomatoes"].size_m[2]) / 0.3952150344848633 - float(city.dimensions["tomatoes"].size_m[1]) / 0.5560800433158875) < 0.001,
		"Tomato cluster must use one uniform scale on X/Y/Z")
	for i in city.loaded:
		if city.descriptors[i].kind == "greenhouse":
			var crop_panel_count := 0
			for child in city.loaded[i].get_children():
				if String(child.name).begins_with("TomatoCropModel"):
					crop_panel_count += 1
			check(crop_panel_count == 5,
				"Each greenhouse must have a centred tomato cluster and single plants at all four ends")
	check(species.get("park-birch", 0) == 12 and species.get("park-pine", 0) == 12 and species.get("park-beech", 0) == 12,
		"West garden must mix birch, pine and beech evenly")
	check(beech_bark_silvers.size() == 4 and beech_leaf_greens.size() == 4,
		"Beeches must have silver bark/branches and four green leaf shades")
	check(pine_count == 12, "Twelve pines must retain their separate brown trunk and green needle meshes")
	var scale_mean := 0.0
	for tree_scale in tree_scales:
		scale_mean += tree_scale
	scale_mean /= tree_scales.size()
	var scale_variance := 0.0
	for tree_scale in tree_scales:
		scale_variance += pow(tree_scale - scale_mean, 2)
	var scale_stddev := sqrt(scale_variance / tree_scales.size())
	check(tree_scales.size() == 36 and scale_stddev > 0.10 and scale_stddev < 0.19,
		"Tree scale must vary with a bounded standard deviation near 15%")
	check(birch_greens.size() == 5, "Birch leaves must be tinted across five green shades")
	for x in range(-80, 81, 10):
		for z in range(-80, 81, 10):
			if Vector2(x, z).length() < 95.0:
				check(absf(terrain.height_at(x, z + 25) - terrain.city_level) < 0.001, "City interior must be level")
	check(absf(terrain.raw_height(160, 25) - terrain.natural_height(160, 25)) < 0.001, "Outside blend: original DTM must be intact")
	var modules: Dictionary = city.dimensions
	check(absf(float(modules["block-of-flats"].size_m[0]) - 18.35778465270996) < 0.01 and
		absf(float(modules["block-of-flats"].size_m[1]) - 36.0) < 0.01 and
		absf(float(modules["block-of-flats"].size_m[2]) - 18.949895095825195) < 0.01,
		"Apartment blocks must be enlarged uniformly by 20 percent")
	check(absf(float(modules["central-house"].size_m[2]) - 51.0) < 0.01, "Central house must be 1.5 times its original 34 m width")
	check(absf(float(modules["park-birch"].size_m[1]) - 7.5) < 0.01, "Birch size must remain unchanged")
	check(absf(float(modules["park-pine"].size_m[1]) - 13.5) < 0.01 and absf(float(modules["park-beech"].size_m[1]) - 12.0) < 0.01,
		"Pines and beeches must be 1.5 times their former height")
	for kind: String in modules:
		check(modules[kind].original_triangles == modules[kind].triangles, "Preserve source geometry: " + kind)
	for descriptor: Dictionary in city.descriptors:
		var size: Array = modules[descriptor.kind].size_m
		var width: float = descriptor.get("span", size[0])
		for x in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var corner := Vector3(width * x, 0, float(size[2]) * z).rotated(Vector3.UP, descriptor.yaw)
				var point: Vector2 = descriptor.point - city.Site.CENTER + Vector2(corner.x, corner.z)
				check(point.length() < 100.0, "Entire footprint must fit on city pad: " + descriptor.kind)
				check(float(size[1]) + descriptor.lift + 1.5 < preload("res://scripts/tycho_dome.gd").roof_height(point.length()),
					"Roof must clear every building/tree corner, including masts: " + descriptor.kind)
		if descriptor.kind == "link-between-block-of-flats":
			check(absf(descriptor.lift + float(size[1]) * 0.5 - 24.0) < 0.01, "Connectors must sit at 2/3 tower height")
	var dome := city.ground_details.get_node("TychoDome")
	check(dome.panel_count == 912 and dome.THICKNESS == 0.24, "Dome must have separate thick triangular glass panels")
	var lamps := city.ground_details.get_node("CityStreetLamps")
	var mist := city.ground_details.get_node("TychoLowMist")
	check(mist.get_meta("height_m") == 1.0 and mist.get_meta("width_m") == 188.0 and mist.get_meta("fog_type") == "volumetric_air_column",
		"Low city air must be a one-metre volumetric column, not mist cards")
	var weather := city.ground_details.get_node("TychoWeather")
	check(weather.get_meta("drop_count") == 112 and weather.get_meta("gravity") == 1.62 and weather.get_meta("local_radius") == 18.0,
		"Tycho weather must use local rain and lunar gravity")
	check(city.ground_details.get_node("TychoVolumetricClouds") != null and weather.get_node("RainDrops") != null,
		"Volumetric clouds and rain must be active under the dome")
	check(lamps.get_meta("lamp_count") == 18, "City streets must have eighteen lamps clear of intersections")
	check(lamps.HEIGHT_M == 6.0, "Street lamps must be six metres high")
	check(absf(lamps.LIGHT_OFFSET.z - 0.9) < 0.001 and absf(lamps.LIGHT_OFFSET.y - 5.825) < 0.001,
		"Flat lamp diffuser must sit 0.9 m out and 5.825 m high")
	check(absf(lamps.DIFFUSER_SIZE.x - 0.205) < 0.001 and absf(lamps.DIFFUSER_SIZE.z - 0.76) < 0.001 and absf(lamps.LIGHT_OFFSET.z - 0.9) < 0.001 and absf(lamps.DIFFUSER_ROTATION - PI) < 0.001,
		"Street lamp diffusers must be narrow, extended by 10 cm at each end, and offset 0.9 m outward")
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, terrain.city_level + 10, 0), Vector3(0, terrain.city_level - 5, 0))
	var hit := root.world_3d.direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and absf(hit.get("position", Vector3.ZERO).y - terrain.city_level) < 0.01,
		"Walking collision must match the flattened ground")
	ray = PhysicsRayQueryParameters3D.create(Vector3(-56, terrain.city_level + 45, 63), Vector3(-56, terrain.city_level - 1, 63))
	hit = root.world_3d.direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and absf(hit.get("position", Vector3.ZERO).y - terrain.city_level - 36.0) < 0.01,
		"Apartment blocks must have solid exterior collision")
	terrain.update_focus(Vector3(2000, 0, 2000))
	await process_frame
	await process_frame
	check(city.loaded.is_empty() and city.scenes.is_empty(), "Distant city nodes and resources must unload")
	terrain.update_focus(Vector3.ZERO)
	deadline = Time.get_ticks_msec() + 60000
	while city.loaded.size() != city.descriptors.size() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(city.loaded.size() == city.descriptors.size(), "Returning to Tycho must reload the city")
	print("TYCHO CITY TEST: %d failures; %d modules; pad elevation %.3f m" % [failures, city.loaded.size(), terrain.city_level])
	quit(1 if failures else 0)
