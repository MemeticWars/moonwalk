extends Node3D
## Six cube faces: stable at poles and the date line, refined around the camera.
const R := 1737400.0
const CELLS := 16
const MAX_LEVEL := 12
const AXES := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
var terrain: Node3D
var patches: Dictionary = {}
var wanted: Dictionary = {}
var pending: Array[Vector4i] = []
var view := Vector3(0, 0, 4.1)
var planned_view := Vector3.INF
var local_frame := false
var local_hole := Vector4.ZERO
var ready_for_view := false
var sampling_level := 0
var retiring: Array[Node] = []
var detail_blend := 0.0
var reference_radius := 1.0
var max_patch_usec := 0

func direction(face: int, u: float, v: float) -> Vector3:
	var n: Vector3 = AXES[face]
	var east := Vector3.UP.cross(n) if absf(n.y) < 0.5 else Vector3.RIGHT
	var north := n.cross(east)
	return (n + east * u + north * v).normalized()

func _select(key: Vector4i) -> void:
	var width := 2.0 / float(1 << key.y)
	var mid := direction(key.x, -1.0 + (key.z + 0.5) * width, -1.0 + (key.w + 0.5) * width)
	if key.y < MAX_LEVEL and view.distance_to(mid * reference_radius) < width * 1.8:
		for y in 2:
			for x in 2:
				_select(Vector4i(key.x, key.y + 1, key.z * 2 + x, key.w * 2 + y))
	else:
		wanted[key] = true

func update_view(p: Vector3, delta: float) -> void:
	view = p
	var tolerance := maxf(0.00004, (view.length() - 1.0) * 0.06)
	if planned_view.distance_to(view) > tolerance:
		planned_view = view
		wanted.clear()
		for face in 6:
			_select(Vector4i(face, 0, 0, 0))
		pending.clear()
		for key: Vector4i in wanted:
			if not patches.has(key): pending.append(key)
		pending.sort_custom(func(a: Vector4i, b: Vector4i) -> bool: return _distance(a) < _distance(b))
		ready_for_view = false
	var started := Time.get_ticks_usec()
	while not pending.is_empty() and Time.get_ticks_usec() - started < 5000:
		var key: Vector4i = pending.pop_front()
		var job_start := Time.get_ticks_usec()
		var patch := _build(key)
		max_patch_usec = maxi(max_patch_usec,Time.get_ticks_usec()-job_start)
		patches[key] = patch
		add_child(patch)
	for patch: MeshInstance3D in patches.values():
		var growth := minf(1.0, float(patch.get_meta("growth")) + delta / 0.65)
		patch.set_meta("growth", growth)
		patch.material_override.set_shader_parameter("growth", growth)
		patch.material_override.set_shader_parameter("detail_blend", detail_blend)
		patch.material_override.set_shader_parameter("local_hole", local_hole)
	if pending.is_empty():
		ready_for_view = true
		for old in retiring: old.queue_free()
		retiring.clear()
		for key: Vector4i in patches.keys():
			if not wanted.has(key):
				patches[key].queue_free()
				patches.erase(key)

func _distance(key: Vector4i) -> float:
	var width := 2.0 / float(1 << key.y)
	return view.distance_to(direction(key.x, -1.0 + (key.z + 0.5) * width, -1.0 + (key.w + 0.5) * width))

func height(n: Vector3) -> float:
	var lat := rad_to_deg(asin(clampf(n.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(n.x, n.z))
	return terrain.elevation(lat, lon) if sampling_level >= 5 else terrain.coarse_elevation(lat, lon)

func local_detail(n: Vector3, meso_height: float) -> float:
	var lat := rad_to_deg(asin(clampf(n.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(n.x, n.z))
	if local_frame:
		var x := deg_to_rad(wrapf(lon - terrain.anchor_lon, -180, 180)) * R * cos(deg_to_rad(terrain.anchor_lat))
		var z := deg_to_rad(terrain.anchor_lat - lat) * R
		if absf(x) < 2200.0 and absf(z) < 2200.0:
			return terrain.base_elevation + terrain.raw_height(x, z) - meso_height
		# The same procedural regolith supplements LOLA along the entire approach,
		# at any landing coordinate, not just inside a named survey patch.
		var radius := Vector2(x,z).length()
		if radius < 32000.0:
			return (terrain.noise.get_noise_2d(x,z)*15.0+terrain.detail.get_noise_2d(x,z)*0.6)*(1.0-smoothstep(24000.0,32000.0,radius))
	return 0.0

func _build(key: Vector4i) -> MeshInstance3D:
	sampling_level = key.y
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var radii := PackedVector2Array()
	var details := PackedVector2Array()
	var fine_normals := PackedColorArray()
	var indices := PackedInt32Array()
	var width := 2.0 / float(1 << key.y)
	var step := width / CELLS
	# Sample one-cell halo for normals; shared grid samples prevent tile-edge steps.
	var grid: Dictionary = {}
	var detail_grid: Dictionary = {}
	for y in range(-1, CELLS + 2):
		for x in range(-1, CELLS + 2):
			var n := direction(key.x, -1.0 + key.z * width + x * step, -1.0 + key.w * width + y * step)
			var h := height(n)
			grid[Vector2i(x,y)] = n * (1.0 + h / R)
			detail_grid[Vector2i(x,y)] = local_detail(n,h) / R
	for y in CELLS + 1:
		for x in CELLS + 1:
			var p: Vector3 = grid[Vector2i(x,y)]
			vertices.append(p)
			var dx: Vector3 = grid[Vector2i(x+1,y)] - grid[Vector2i(x-1,y)]
			var dy: Vector3 = grid[Vector2i(x,y+1)] - grid[Vector2i(x,y-1)]
			normals.append(dx.cross(dy).normalized())
			var gx1: Vector3 = grid[Vector2i(x+1,y)]
			var gx0: Vector3 = grid[Vector2i(x-1,y)]
			var gy1: Vector3 = grid[Vector2i(x,y+1)]
			var gy0: Vector3 = grid[Vector2i(x,y-1)]
			var fine_dx: Vector3 = gx1+gx1.normalized()*float(detail_grid[Vector2i(x+1,y)])-gx0-gx0.normalized()*float(detail_grid[Vector2i(x-1,y)])
			var fine_dy: Vector3 = gy1+gy1.normalized()*float(detail_grid[Vector2i(x,y+1)])-gy0-gy0.normalized()*float(detail_grid[Vector2i(x,y-1)])
			var fine_normal := fine_dx.cross(fine_dy).normalized()*0.5+Vector3.ONE*0.5
			fine_normals.append(Color(fine_normal.x,fine_normal.y,fine_normal.z,1.0))
			var n := p.normalized()
			uv.append(Vector2(atan2(n.x,n.z) / TAU + 0.5, 0.5 - asin(clampf(n.y,-1,1)) / PI))
			var low := Vector2i(x - x % 2, y - y % 2)
			var high := Vector2i(mini(low.x+2,CELLS), mini(low.y+2,CELLS))
			var a: Vector3 = grid[low].lerp(grid[Vector2i(high.x,low.y)], float(x%2)*0.5)
			var b: Vector3 = grid[Vector2i(low.x,high.y)].lerp(grid[high], float(x%2)*0.5)
			radii.append(Vector2(a.lerp(b,float(y%2)*0.5).length(), p.length()))
			var da := lerpf(detail_grid[low],detail_grid[Vector2i(high.x,low.y)],float(x%2)*0.5)
			var db := lerpf(detail_grid[Vector2i(low.x,high.y)],detail_grid[high],float(x%2)*0.5)
			details.append(Vector2(detail_grid[Vector2i(x,y)],lerpf(da,db,float(y%2)*0.5)))
	for y in CELLS:
		for x in CELLS:
			var a := y * (CELLS+1) + x
			indices.append_array(PackedInt32Array([a,a+CELLS+1,a+1,a+1,a+CELLS+1,a+CELLS+2]))
	# A separate caster uses only real ground, without the artificial skirts.
	var ground_count := vertices.size()
	var ground_indices := indices.duplicate()
	# Radial skirts close T-junctions between neighbouring refinement levels.
	for side in 4:
		for i in CELLS:
			var a := i if side == 0 else (CELLS*(CELLS+1)+i if side == 1 else i*(CELLS+1)+(CELLS if side == 2 else 0))
			var b := a + (1 if side < 2 else CELLS+1)
			var start := vertices.size()
			for j in [a,b,a,b]:
				var depth := step * 0.4 if vertices.size() - start >= 2 else 0.0
				vertices.append(vertices[j].normalized() * (vertices[j].length()-depth))
				normals.append(normals[j])
				uv.append(uv[j])
				radii.append(radii[j]-Vector2.ONE*depth)
				details.append(details[j])
				fine_normals.append(fine_normals[j])
			indices.append_array(PackedInt32Array([start,start+1,start+2,start+1,start+3,start+2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = radii
	arrays[Mesh.ARRAY_TEX_UV2] = details
	arrays[Mesh.ARRAY_COLOR] = fine_normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var patch := MeshInstance3D.new()
	patch.mesh = mesh
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/meso.gdshader")
	mat.set_shader_parameter("lunar_albedo", preload("res://scripts/lunar_regional_color.gd").get_texture())
	mat.set_shader_parameter("detail_blend", detail_blend)
	mat.set_shader_parameter("anchor", Vector2(deg_to_rad(terrain.anchor_lat),deg_to_rad(terrain.anchor_lon)))
	mat.set_shader_parameter("local_frame", local_frame)
	mat.set_shader_parameter("local_hole", local_hole)
	patch.material_override = mat
	var shadow_arrays := arrays.duplicate()
	shadow_arrays[Mesh.ARRAY_VERTEX] = vertices.slice(0,ground_count)
	shadow_arrays[Mesh.ARRAY_NORMAL] = normals.slice(0,ground_count)
	shadow_arrays[Mesh.ARRAY_TEX_UV] = radii.slice(0,ground_count)
	shadow_arrays[Mesh.ARRAY_TEX_UV2] = details.slice(0,ground_count)
	shadow_arrays[Mesh.ARRAY_COLOR] = fine_normals.slice(0,ground_count)
	shadow_arrays[Mesh.ARRAY_INDEX] = ground_indices
	var caster := MeshInstance3D.new()
	caster.name = "TerrainShadow"
	var shadow_mesh := ArrayMesh.new()
	shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,shadow_arrays)
	caster.mesh = shadow_mesh
	caster.material_override = mat
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	patch.add_child(caster)
	patch.set_meta("growth", 0.0)
	return patch

func reset_for_surface(source: Node3D) -> void:
	terrain = source
	local_frame = true
	ready_for_view = false
	planned_view = Vector3.INF
	for patch: Node in patches.values(): retiring.append(patch)
	patches.clear()
