extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := preload("res://scripts/lunar_terrain.gd").new()
	terrain.colony = {"name": "Tycho Station", "latitude": -43.66, "longitude": -11.3}
	root.add_child(terrain)
	terrain.set_process(false)
	var key: Vector2i = terrain.center
	var near_tile := terrain._build_ground(key, 0)
	var far_tile := terrain._build_ground(key + Vector2i.RIGHT, 1)
	var a: PackedVector3Array = near_tile.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = far_tile.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for z in 33:
		assert(a[z * 33 + 32].is_equal_approx(b[z * 33]), "Local LOD edges must share every 2 m vertex")
	near_tile.free()
	far_tile.free()
	var horizon := preload("res://scripts/lunar_horizon.gd").new()
	horizon.terrain = terrain
	horizon._replan()
	var bounds := Rect2(Vector2(terrain.center - Vector2i.ONE * terrain.FAR_RADIUS) * 64,
		Vector2.ONE * (2 * terrain.FAR_RADIUS + 1) * 64)
	for patch: Vector3i in horizon.wanted:
		if bounds.intersects(Rect2(patch.x, patch.y, patch.z, patch.z)):
			assert(patch.z == 64, "A coarse horizon parent must not cover walking tiles")
	# Test actual fine/coarse triangles, not just shared endpoints. Reverse
	# planning order too: a deterministic seam must not depend on insertion order.
	var fine := Vector3i(-320, -1408, 64)
	var coarse := Vector3i(-256, -1408, 128)
	var first := PackedVector3Array()
	for reverse in [false, true]:
		horizon.wanted.clear()
		for patch: Vector3i in ([coarse, fine] if reverse else [fine, coarse]):
			horizon.wanted[patch] = true
		var mesh := horizon._build_patch(fine)
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for z in 33:
			var p := vertices[z * 33 + 32]
			var low := floorf(p.z / 16.0) * 16.0
			var expected := lerpf(terrain.raw_height(p.x, low), terrain.raw_height(p.x, low + 16), (p.z - low) / 16)
			assert(absf(p.y - expected) < 0.001, "Fine edge must lie on the coarse triangle edge")
		if reverse:
			assert(vertices == first, "Build order changed the mesh")
		else:
			first = vertices
		mesh.free()
	horizon.free()
	# Initial terrain already exists when city pads are registered.
	var pad_center := Vector2(key.x * 64 + 32, key.y * 64 + 32)
	terrain.add_city_pad(pad_center, 90, 20, 80, terrain.city_level + 15)
	await process_frame
	var rebuilt: PackedVector3Array = terrain.tiles[key].get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in 1089:
		var p := rebuilt[i]
		assert(absf(p.y - terrain.height_at(p.x, p.z)) < 0.001, "Pad left an obsolete floating terrain tile")
	terrain.free()
	print("TERRAIN SEAMS PASS: local edges, horizon overlap, coarse-edge stitching, deterministic order, pad rebuild")
	quit()
