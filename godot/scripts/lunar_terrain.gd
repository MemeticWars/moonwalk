extends Node3D

const ColonyUtil := preload("res://scripts/colony_util.gd")
const TychoSite := preload("res://scripts/tycho_site.gd")
const MesoDEM := preload("res://scripts/lunar_meso_dem.gd")
var city_enabled := false
var city_level := 0.0
## Hand-authored crater art, kept for Silesia only. Every other colony gets a
## seeded procedural set instead, so a new sector needs no manual art pass.
const SILESIA_CRATERS: Array[Vector4] = [Vector4(-47, -66, 31, 7), Vector4(64, -104, 53, 12),
	Vector4(114, 40, 24, 5), Vector4(-132, 30, 67, 13), Vector4(5, 143, 41, 8),
	Vector4(-176, -170, 92, 20), Vector4(207, -180, 75, 18)]
const TILE := 64.0
const NEAR_RADIUS := 2
const FAR_RADIUS := 5
const STEP := 2.0
var colony: Dictionary = {}
var anchor_lat := -82.0
var anchor_lon := 30.0
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var craters: Array[Vector4] = []
var material: ShaderMaterial
var dem := PackedFloat32Array()
var tiles: Dictionary = {}
var queue: Array[Vector3i] = []
var center := Vector2i(99999, 99999)
var focus := Vector3.ZERO
var base_elevation := 0.0
var active := true
var unloaded_count := 0
var sector_path := "res://assets/sectors/silesia"
var sector_info: Dictionary = {}
var source_cache: Dictionary = {}
var rock_mesh: SphereMesh
var stream: Node
var incoming: Dictionary = {}
var road_grading_by_tile: Dictionary = {}
var road_grading_count := 0
var road_cuts_by_tile: Dictionary = {}
const SURVEY_BLEND_M := 256.0
var local_sources: Dictionary = {}

func _ready() -> void:
	var colony_name: String = colony.get("name", "Silesia")
	var is_silesia := colony_name == "Silesia"
	var slug := ColonyUtil.slug(colony_name)
	anchor_lat = colony.get("latitude", anchor_lat)
	anchor_lon = colony.get("longitude", anchor_lon)
	sector_path = "res://assets/sectors/%s" % slug
	noise.seed = 704 if is_silesia else hash(slug + "_macro")
	noise.frequency = 0.008
	noise.fractal_octaves = 4
	detail.seed = 319 if is_silesia else hash(slug + "_detail")
	detail.frequency = 0.09
	detail.fractal_octaves = 3
	dem = FileAccess.get_file_as_bytes("res://assets/moon/height_m.bin").to_float32_array()
	base_elevation = elevation(anchor_lat, anchor_lon)
	stream = preload("res://scripts/terrain_stream.gd").new()
	add_child(stream)
	stream.tile_available.connect(_remote_ready)
	if not is_silesia:
		stream.set_sector(slug)
	if FileAccess.file_exists(sector_path + "/sector.json"):
		sector_info = JSON.parse_string(FileAccess.get_file_as_string(sector_path + "/sector.json"))
		base_elevation = sector_info.get("anchor_dem_elevation_m", base_elevation)
		for filename in DirAccess.get_files_at(sector_path):
			if filename.ends_with(".bin"):
				var parts := filename.trim_suffix(".bin").split("_")
				if parts.size() == 2:
					local_sources[Vector2i(int(parts[0]), int(parts[1]))] = true
	craters.clear()
	if is_silesia:
		for crater: Vector4 in SILESIA_CRATERS:
			craters.append(crater)
	var rng := RandomNumberGenerator.new()
	rng.seed = 520 if is_silesia else hash(slug + "_craters")
	for i in 95:
		var p := Vector2(rng.randf_range(-310, 310), rng.randf_range(-310, 310))
		if p.length() > 22:
			var radius := rng.randf_range(2.5, 13.0)
			craters.append(Vector4(p.x, p.y, radius, radius * 0.17))
	city_enabled = colony_name == "Tycho Station"
	if city_enabled:
		# Median surveyed level balances excavation/fill without changing the DEM.
		var levels: Array[float] = []
		for z in range(-80, 81, 20):
			for x in range(-80, 81, 20):
				if Vector2(x, z).length() <= 80.0:
					levels.append(natural_height(x + TychoSite.CENTER.x, z + TychoSite.CENTER.y))
		levels.sort()
		city_level = levels[levels.size() / 2]
	_prepare_materials()
	update_focus(Vector3.ZERO)
	# Spawn collision is ready before the player is added.
	for i in 9:
		_build_next()

func _process(_delta: float) -> void:
	if active:
		for key: Vector2i in incoming.keys():
			if maxi(absi(key.x - center.x), absi(key.y - center.y)) > 2:
				incoming.erase(key)
				_refresh_source(key)
		_build_next()

func _remote_ready(key: Vector2i) -> void:
	# Never replace terrain directly under a walking/jumping character.
	if maxi(absi(key.x - center.x), absi(key.y - center.y)) <= 2:
		incoming[key] = true
	else:
		_refresh_source(key)

func _refresh_source(key: Vector2i) -> void:
	source_cache.erase(key)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var p := key + Vector2i(dx, dz)
			if tiles.has(p):
				var job := Vector3i(p.x, p.y, tiles[p].get_meta("lod"))
				if not queue.has(job):
					queue.append(job)

func update_focus(point: Vector3) -> void:
	focus = point
	var next := Vector2i(floori(point.x / TILE), floori(point.z / TILE))
	if next == center:
		return
	center = next
	stream.set_focus(center)
	queue.clear()
	var wanted: Dictionary = {}
	for z in range(-FAR_RADIUS, FAR_RADIUS + 1):
		for x in range(-FAR_RADIUS, FAR_RADIUS + 1):
			var key := center + Vector2i(x, z)
			var lod := 0 if maxi(absi(x), absi(z)) <= NEAR_RADIUS else 1
			wanted[key] = lod
			stream.enqueue(key)
			if not tiles.has(key) or tiles[key].get_meta("lod") != lod:
				queue.append(Vector3i(key.x, key.y, lod))
	for key: Vector2i in tiles.keys():
		if not wanted.has(key):
			tiles[key].queue_free()
			tiles.erase(key)
			unloaded_count += 1
	# Disk height tiles are released too, with a one-tile border for sampling normals.
	for key: Vector2i in source_cache.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > FAR_RADIUS + 1:
			source_cache.erase(key)
	queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return Vector2(a.x - center.x, a.y - center.y).length_squared() < Vector2(b.x - center.x, b.y - center.y).length_squared())

func has_ground(point: Vector3) -> bool:
	var key := Vector2i(floori(point.x / TILE), floori(point.z / TILE))
	return tiles.has(key) and tiles[key].get_meta("lod") == 0

func set_coverage(value: bool) -> void:
	material.set_shader_parameter("coverage", value)
	for tile: Node3D in tiles.values():
		for child in tile.get_children():
			if child is MeshInstance3D and child.material_override is ShaderMaterial:
				child.material_override.set_shader_parameter("coverage", value)

func _build_next() -> void:
	if queue.is_empty():
		return
	var job: Vector3i = queue.pop_front()
	var key := Vector2i(job.x, job.y)
	var tile := _build_ground(key, job.z)
	if tiles.has(key):
		tiles[key].queue_free()
	tiles[key] = tile
	add_child(tile)

func local_dem_height(x: float, z: float) -> float:
	if sector_info.is_empty() and not stream.enabled:
		return NAN
	var key := Vector2i(floori(x / TILE), floori(z / TILE))
	# Distant procedural tiles must not fill the source cache with missing files.
	if not local_sources.has(key) and not stream.enabled:
		return NAN
	if not source_cache.has(key):
		var path := sector_path + "/%d_%d.bin" % [key.x, key.y]
		var remote: Dictionary = stream.read_tile(key) if not incoming.has(key) else {}
		if not remote.is_empty():
			source_cache[key] = Marshalls.base64_to_raw(remote.height_f32).to_float32_array()
		else:
			source_cache[key] = FileAccess.get_file_as_bytes(path).to_float32_array() if FileAccess.file_exists(path) else PackedFloat32Array()
	var values: PackedFloat32Array = source_cache[key]
	if source_cache.size() > 256:
		for old: Vector2i in source_cache.keys():
			if old != key and maxi(absi(old.x - center.x), absi(old.y - center.y)) > FAR_RADIUS + 1:
				source_cache.erase(old)
				if source_cache.size() <= 256:
					break
	if values.size() != 1089 and values.size() != 1225:
		return NAN
	var stride := 35 if values.size() == 1225 else 33
	var halo := 1 if stride == 35 else 0
	var gx := (x - key.x * TILE) / STEP
	var gz := (z - key.y * TILE) / STEP
	var ix := mini(int(gx), 31)
	var iz := mini(int(gz), 31)
	var index := (iz + halo) * stride + ix + halo
	return lerpf(lerpf(values[index], values[index + 1], gx - ix), lerpf(values[index + stride], values[index + stride + 1], gx - ix), gz - iz)

func elevation(latitude: float, longitude: float) -> float:
	var meso := MesoDEM.sample(latitude, longitude)
	if not is_nan(meso):
		return meso
	return coarse_elevation(latitude, longitude)

func coarse_elevation(latitude: float, longitude: float) -> float:
	var u := fposmod((longitude + 180.0) / 360.0, 1.0) * 1440.0 - 0.5
	var v := clampf((90.0 - latitude) / 180.0 * 720.0 - 0.5, 0, 719)
	var x0 := posmod(int(floor(u)), 1440)
	var x1 := (x0 + 1) % 1440
	var y0 := int(floor(v))
	var y1 := mini(y0 + 1, 719)
	return lerpf(lerpf(dem[y0 * 1440 + x0], dem[y0 * 1440 + x1], u - floor(u)), lerpf(dem[y1 * 1440 + x0], dem[y1 * 1440 + x1], u - floor(u)), v - floor(v))

func latlon_at(x: float, z: float) -> Vector2:
	# Local tangent patch at the active colony's site. The single place world
	# metres map to selenographic degrees.
	var lat := anchor_lat - rad_to_deg(z / 1737400.0)
	var lon := anchor_lon + rad_to_deg(x / (1737400.0 * cos(deg_to_rad(anchor_lat))))
	return Vector2(lat, lon)

func natural_height(x: float, z: float) -> float:
	var surveyed := local_dem_height(x, z)
	var weight := survey_weight(x, z) if not is_nan(surveyed) else 0.0
	if weight >= 1.0:
		return surveyed
	var fallback := procedural_height(x, z)
	return lerpf(fallback, surveyed, weight) if weight > 0.0 else fallback

## Metres from (x, z) to the nearest edge of the surveyed 2 m footprint. 0.0
## with no separate survey (e.g. a wilderness landing) -- there's no real 2 m
## patch to already be inside of, so callers gating on that never fire.
func survey_margin(x: float, z: float) -> float:
	var bounds: Array = sector_info.get("tile_key_range", [])
	if bounds.size() != 2:
		return 0.0
	var low := float(bounds[0]) * TILE
	var high := (float(bounds[1]) + 1.0) * TILE
	return minf(minf(x - low, high - x), minf(z - low, high - z))

func survey_weight(x: float, z: float) -> float:
	# Blend inside the surveyed footprint, preserving its central 2 m data.
	# Both endpoints have zero blend slope, avoiding a vertical step at its edge.
	if sector_info.get("tile_key_range", []).size() != 2:
		return 1.0
	return smoothstep(0.0, SURVEY_BLEND_M, survey_margin(x, z))

func procedural_height(x: float, z: float) -> float:
	# Local tangent patch at the fictional Silesia site. LOLA supplies only macro relief.
	var ll := latlon_at(x, z)
	var h := elevation(ll.x, ll.y) - base_elevation
	h += noise.get_noise_2d(x, z) * 15.0 + detail.get_noise_2d(x, z) * 0.6
	for c in craters:
		var t := Vector2(x - c.x, z - c.y).length() / c.z
		if t < 1.6:
			h += -c.w * pow(maxf(0, 1.0 - t * t), 2) + c.w * 0.32 * exp(-pow((t - 1.0) / 0.16, 2))
	return h

func add_road_grading(points: PackedVector3Array, width: float) -> void:
	var extended := points.duplicate()
	var initial := (points[1] - points[0]).normalized()
	var final := (points[-1] - points[-2]).normalized()
	initial.y = 0.0
	final.y = 0.0
	extended.insert(0, points[0] - initial.normalized() * 16.0)
	extended.append(points[-1] + final.normalized() * 40.0)
	var stations: Array[float] = [-16.0]
	for i in range(1, extended.size()):
		stations.append(stations[-1] + Vector2(extended[i].x - extended[i-1].x, extended[i].z - extended[i-1].z).length())
	var length := stations[-2]
	for i in range(extended.size() - 1):
		var a := extended[i]
		var b := extended[i + 1]
		var low := Vector2(a.x, a.z).min(Vector2(b.x, b.z)) - Vector2.ONE * (width + 16.0)
		var high := Vector2(a.x, a.z).max(Vector2(b.x, b.z)) + Vector2.ONE * (width + 16.0)
		var segment := {"a": a, "b": b, "width": width, "station": stations[i], "span": stations[i+1]-stations[i], "length": length, "id": road_grading_count}
		for z in range(floori(low.y / TILE), floori(high.y / TILE) + 1):
			for x in range(floori(low.x / TILE), floori(high.x / TILE) + 1):
				var key := Vector2i(x, z)
				if not road_grading_by_tile.has(key):
					road_grading_by_tile[key] = []
				road_grading_by_tile[key].append(segment)
	road_grading_count += 1

func _ramp_samples(point: Vector2) -> Dictionary:
	var result := {}
	var key := Vector2i(floori(point.x / TILE), floori(point.y / TILE))
	for segment: Dictionary in road_grading_by_tile.get(key, []):
		var a := Vector2(segment.a.x, segment.a.z)
		var b := Vector2(segment.b.x, segment.b.z)
		var t := clampf((point-a).dot(b-a) / a.distance_squared_to(b), 0.0, 1.0)
		var distance := point.distance_to(a.lerp(b, t))
		if not result.has(segment.id) or distance < result[segment.id].distance:
			result[segment.id] = {"distance": distance, "along": segment.station + t * segment.span, "height": lerpf(segment.a.y, segment.b.y, t), "width": segment.width, "length": segment.length}
	return result

func add_road_cut(a: Vector3, b: Vector3, width: float) -> void:
	var low := Vector2(a.x, a.z).min(Vector2(b.x, b.z)) - Vector2.ONE * (width + 12.0)
	var high := Vector2(a.x, a.z).max(Vector2(b.x, b.z)) + Vector2.ONE * (width + 12.0)
	var cut := {"a": a, "b": b, "width": width}
	for z in range(floori(low.y / TILE), floori(high.y / TILE) + 1):
		for x in range(floori(low.x / TILE), floori(high.x / TILE) + 1):
			var key := Vector2i(x, z)
			if not road_cuts_by_tile.has(key):
				road_cuts_by_tile[key] = []
			road_cuts_by_tile[key].append(cut)

func raw_height(x: float, z: float) -> float:
	var result := natural_height(x, z)
	if city_enabled:
		result = lerpf(result, city_level, TychoSite.weight(x, z))
	var point := Vector2(x, z)
	var key := Vector2i(floori(x / TILE), floori(z / TILE))
	for cut: Dictionary in road_cuts_by_tile.get(key, []):
		var a := Vector2(cut.a.x, cut.a.z)
		var b := Vector2(cut.b.x, cut.b.z)
		var t := clampf((point - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
		var distance := point.distance_to(a.lerp(b, t))
		var weight := 1.0 - smoothstep(cut.width, cut.width + 12.0, distance)
		result = lerpf(result, minf(result, lerpf(cut.a.y, cut.b.y, t) - 0.2), weight)
	for ramp: Dictionary in _ramp_samples(point).values():
		var weight := (1.0 - smoothstep(ramp.width, ramp.width + 16.0, ramp.distance)) * smoothstep(-16.0, 0.0, ramp.along) * (1.0 - smoothstep(ramp.length + 20.0, ramp.length + 40.0, ramp.along))
		var profile: float = ramp.height - 0.2 * (1.0 - smoothstep(ramp.length - 8.0, ramp.length, ramp.along))
		result = lerpf(result, profile, weight)
	return result

func road_reserved(x: float, z: float) -> bool:
	var point := Vector2(x, z)
	var key := Vector2i(floori(x / TILE), floori(z / TILE))
	for cut: Dictionary in road_cuts_by_tile.get(key, []):
		var a := Vector2(cut.a.x, cut.a.z)
		var b := Vector2(cut.b.x, cut.b.z)
		var t := clampf((point-a).dot(b-a) / a.distance_squared_to(b), 0.0, 1.0)
		if point.distance_to(a.lerp(b, t)) <= cut.width + 2.0:
			return true
	for ramp: Dictionary in _ramp_samples(Vector2(x, z)).values():
		if ramp.along >= -4.0 and ramp.along <= ramp.length + 40.0 and ramp.distance <= ramp.width + 2.0:
			return true
	return false

func refresh_road_grading() -> void:
	# Called before actors spawn; rebuild the already prepared terrain/colliders.
	for key: Vector2i in tiles.keys():
		var lod: int = tiles[key].get_meta("lod")
		tiles[key].free()
		tiles[key] = _build_ground(key, lod)
		add_child(tiles[key])

func height_at(x: float, z: float) -> float:
	# Same triangle interpolation as the rendered/collision mesh.
	var gx := x / STEP
	var gz := z / STEP
	var ix := floori(gx)
	var iz := floori(gz)
	var tx := gx - ix
	var tz := gz - iz
	var a := raw_height(ix * STEP, iz * STEP)
	var b := raw_height((ix + 1) * STEP, iz * STEP)
	var c := raw_height(ix * STEP, (iz + 1) * STEP)
	var d := raw_height((ix + 1) * STEP, (iz + 1) * STEP)
	if tx + tz <= 1:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1 - tx) + (b - d) * (1 - tz)

func _build_ground(key: Vector2i, lod: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Tile_%d_%d_LOD%d" % [key.x, key.y, lod]
	root.set_meta("lod", lod)
	var cells := 32 if lod == 0 or road_grading_by_tile.has(key) else 8
	var step := TILE / cells
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var meso_heights := PackedVector2Array()
	for z in cells + 1:
		for x in cells + 1:
			var px := key.x * TILE + x * step
			var pz := key.y * TILE + z * step
			var h := raw_height(px, pz)
			vertices.append(Vector3(px, h, pz))
			var ll := latlon_at(px,pz)
			meso_heights.append(Vector2(elevation(ll.x,ll.y)-base_elevation,0.0))
			colors.append(Color(survey_weight(px, pz), 0.0, 0.0, 1.0))
			uvs.append(Vector2(x, z) / float(cells))
			var dx := raw_height(px + STEP, pz) - raw_height(px - STEP, pz)
			var dz := raw_height(px, pz + STEP) - raw_height(px, pz - STEP)
			normals.append(Vector3(-dx, 2 * STEP, -dz).normalized())
	for z in cells:
		for x in cells:
			var a := z * (cells + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + cells + 1, a + 1, a + cells + 2, a + cells + 1]))
	# Downward skirts conceal cracks between unequal tessellation levels.
	for side in 4:
		for i in cells:
			var a: int
			var b: int
			match side:
				0: a = i; b = i + 1
				1: a = i * (cells + 1) + cells; b = (i + 1) * (cells + 1) + cells
				2: a = cells * (cells + 1) + i + 1; b = a - 1
				_: a = (i + 1) * (cells + 1); b = i * (cells + 1)
			var idx := vertices.size()
			vertices.append_array(PackedVector3Array([vertices[a], vertices[b], vertices[a] - Vector3.UP * 6, vertices[b] - Vector3.UP * 6]))
			colors.append_array(PackedColorArray([colors[a], colors[b], colors[a], colors[b]]))
			normals.append_array(PackedVector3Array([normals[a], normals[b], normals[a], normals[b]]))
			uvs.append_array(PackedVector2Array([uvs[a], uvs[b], uvs[a], uvs[b]]))
			meso_heights.append_array(PackedVector2Array([meso_heights[a],meso_heights[b],meso_heights[a]-Vector2(6,0),meso_heights[b]-Vector2(6,0)]))
			indices.append_array(PackedInt32Array([idx, idx + 2, idx + 1, idx + 1, idx + 2, idx + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = meso_heights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	surface.material_override = material
	# Do not load orthophoto textures: their cast shadows would be baked into the
	# regolith under a differently positioned in-game Sun.
	root.add_child(surface)
	if lod == 0:
		surface.create_trimesh_collision()
		_build_rocks(root, key)
	return root

func _prepare_materials() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/regolith.gdshader")
	material.set_shader_parameter("regional_albedo", preload("res://scripts/lunar_regional_color.gd").get_texture())
	material.set_shader_parameter("region_anchor", Vector2(deg_to_rad(anchor_lat),deg_to_rad(anchor_lon)))
	var grain := NoiseTexture2D.new()
	grain.width = 2048
	grain.height = 2048
	grain.generate_mipmaps = true
	grain.seamless = true
	var n := FastNoiseLite.new()
	n.seed = 97
	n.frequency = 0.32
	n.fractal_octaves = 5
	grain.noise = n
	material.set_shader_parameter("grain", grain)
	rock_mesh = SphereMesh.new()
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 3
	rock_mesh.radius = 0.6
	rock_mesh.height = 1.0
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.24, 0.235, 0.225)
	rock_mat.roughness = 1.0
	rock_mesh.material = rock_mat

func _build_rocks(root: Node3D, key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 5719
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock_mesh
	mm.instance_count = 48
	for i in mm.instance_count:
		var x := key.x * TILE + rng.randf_range(2, 62)
		var z := key.y * TILE + rng.randf_range(2, 62)
		if absf(x) < 5 and absf(z) < 22:
			x += 12
		var s := rng.randf_range(0.1, 0.7)
		if i % 29 == 0:
			s = rng.randf_range(1.1, 2.6)
		if road_reserved(x, z) or (city_enabled and Vector2(x, z).distance_to(TychoSite.CENTER) < TychoSite.RADIUS + 2.0):
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var p := Vector3(x, height_at(x, z) + s * 0.18, z)
		var basis := Basis.from_euler(Vector3(rng.randf(), rng.randf() * TAU, rng.randf())).scaled(Vector3(s * 1.4, s * 0.8, s))
		mm.set_instance_transform(i, Transform3D(basis, p))
		if s > 1.0:
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			var shape := SphereShape3D.new()
			shape.radius = s * 0.56
			col.shape = shape
			body.add_child(col)
			root.add_child(body)
			body.position = p
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	root.add_child(instance)
