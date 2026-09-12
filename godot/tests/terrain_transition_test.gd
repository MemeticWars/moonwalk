extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := preload("res://scripts/lunar_terrain.gd").new()
	terrain.colony = {"name": "Tycho Station", "latitude": -43.66, "longitude": -11.3}
	root.add_child(terrain)
	terrain.set_process(false)
	# Survey interior remains unmodified; all four footprint borders meet the
	# procedural field continuously, including the negative-coordinate boundary.
	assert(is_equal_approx(terrain.natural_height(0, 0), terrain.local_dem_height(0, 0)))
	for edge in [-1536.0, 1600.0]:
		for offset in [-700.0, 0.0, 700.0]:
			for swap in [false, true]:
				var a := Vector2(edge - 0.001, offset)
				var b := Vector2(edge + 0.001, offset)
				if swap:
					a = Vector2(a.y, a.x)
					b = Vector2(b.y, b.x)
				assert(absf(terrain.natural_height(a.x, a.y) - terrain.natural_height(b.x, b.y)) < 0.02, "Survey edge has a height step")
	var far := preload("res://scripts/lunar_horizon.gd").new()
	far.terrain = terrain
	root.add_child(far)
	far.set_process(false)
	var mountain := far._build_patch(Vector3i(4096, 4096, 4096))
	assert(mountain.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)
	assert(mountain.mesh.shadow_mesh != null, "Mountains need a terrain-only shadow mesh")
	var shadow_vertices: PackedVector3Array = mountain.mesh.shadow_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(shadow_vertices.size() == 81, "Artificial LOD skirts must not cast shadows")
	mountain.free()
	for position in [Vector3.ZERO, Vector3(1800, 0, 0), Vector3(-2300, 0, 900)]:
		terrain.update_focus(position)
		far._replan()
		assert(far.wanted.size() < 2000, "Quadtree budget is unbounded")
		# Exactly one leaf covers every sampled point, including the former hole
		# between the 350 m local patch and the 1200 m horizon opening.
		for distance in [0.5, 350.5, 600.5, 1200.5, 3000.5, 15000.5]:
			var sample := Vector2(position.x + distance, position.z + 0.5)
			var count := 0
			for key: Vector3i in far.wanted:
				if Rect2(key.x, key.y, key.z, key.z).has_point(sample):
					count += 1
			assert(count == 1, "Far terrain must have no holes or overlapping leaves")
		var key := Vector2i(floori(position.x / 64), floori(position.z / 64))
		var tile := terrain._build_ground(key, 0)
		root.add_child(tile)
		var mesh: Mesh = tile.get_child(0).mesh
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0, 1089, 32):
			var p := vertices[i]
			assert(absf(p.y - terrain.height_at(p.x, p.z)) < 0.001, "Walking height must match generated terrain")
		tile.free()
	assert(terrain.source_cache.size() <= 256)
	far.free()
	terrain.free()
	print("TERRAIN TRANSITION PASS: survey edges, collision heights, moving LOD coverage and cache budget")
	quit()
