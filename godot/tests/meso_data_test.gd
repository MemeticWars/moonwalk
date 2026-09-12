extends SceneTree
const DEM = preload("res://scripts/lunar_meso_dem.gd")

func _initialize() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEM.PATH+"metadata.json"))
	assert(meta.metres_per_pixel_equator > 470.0 and meta.metres_per_pixel_equator < 475.0)
	for sample: Dictionary in meta.control_samples:
		var lat := 90.0-(float(sample.y)+0.5)*180.0/DEM.HEIGHT
		var lon := (float(sample.x)+0.5)*360.0/DEM.WIDTH-180.0
		assert(absf(DEM.sample(lat,lon)-sample.height_m)<0.01,"Tile decoder must match source TIFF, including edge tiles")
	for lat in [-89.99,-43.66,0.0,89.99]:
		assert(absf(DEM.sample(lat,179.999999)-DEM.sample(lat,-180.000001))<0.01,"Date line wrapping must preserve heights")
	for lon in range(-180,180,3):
		assert(is_finite(DEM.sample(18.0,lon)))
	assert(DEM.cache.size()<=48,"DEM cache must remain below 24 MiB")
	var lod := preload("res://scripts/lunar_orbit_lod.gd").new()
	for direction in [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3(0.3,-0.4,0.5).normalized()]:
		lod.view = direction*1.005
		lod.wanted.clear()
		for face in 6: lod._select(Vector4i(face,0,0,0))
		var areas := PackedFloat64Array([0,0,0,0,0,0])
		for key: Vector4i in lod.wanted:
			areas[key.x] += pow(0.25,key.y)
			var parent := Vector4i(key.x,key.y-1,key.z/2,key.w/2)
			while parent.y >= 0:
				assert(not lod.wanted.has(parent),"LOD leaves must not overlap parents")
				parent = Vector4i(parent.x,parent.y-1,parent.z/2,parent.w/2)
		for area in areas: assert(absf(area-1.0)<0.000001,"Quadtree must cover every face without holes")
		assert(lod.wanted.size()<1500,"Refinement must stay local, including at the poles")
	lod.free()
	var terrain := preload("res://scripts/lunar_terrain.gd").new()
	terrain.colony = {"name":"Landing_shadow_test","latitude":12.5,"longitude":179.95}
	terrain.dem = FileAccess.get_file_as_bytes("res://assets/moon/height_m.bin").to_float32_array()
	var caster_lod := preload("res://scripts/lunar_orbit_lod.gd").new()
	caster_lod.terrain = terrain
	var patch := caster_lod._build(Vector4i(0,0,0,0))
	var caster: MeshInstance3D = patch.get_node("TerrainShadow")
	assert(caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert(caster.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==289,"Only ground, never LOD skirts, may cast shadows")
	assert(caster.material_override==patch.material_override,"Shadow and visible relief must morph together")
	patch.free()
	caster_lod.free()
	terrain.free()
	print("MESO DATA PASS: NASA control samples, 474 m/px, date line, 24 MiB cache, six-face LOD coverage and polar bounds")
	quit()
