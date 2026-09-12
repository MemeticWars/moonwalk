extends Node3D
## Camera-neighbourhood quadtree, sharing the walking terrain height function.
const ROOT_SIZE := 32768
const MIN_SIZE := 64
const CELLS := 8
var terrain: Node3D
var patches: Dictionary = {}
var wanted: Dictionary = {}
var pending: Array[Vector3i] = []
var last_center := Vector2i(99999, 99999)

func _ready() -> void:
	name = "GlobalDemHorizon"

func _process(_delta: float) -> void:
	if terrain == null or not terrain.active:
		return
	if last_center != terrain.center:
		_replan()
	# A bounded job per frame, with nearest patches first.
	if not pending.is_empty():
		var key: Vector3i = pending.pop_front()
		patches[key] = _build_patch(key)
		add_child(patches[key])
	# Retire obsolete parents/children only after the replacement set is ready.
	if pending.is_empty():
		for key: Vector3i in patches.keys():
			if not wanted.has(key):
				patches[key].queue_free()
				patches.erase(key)
	for key: Vector3i in patches:
		var covered: bool = key.z == MIN_SIZE and terrain.tiles.has(Vector2i(key.x / MIN_SIZE, key.y / MIN_SIZE))
		patches[key].visible = not covered

func _replan() -> void:
	last_center = terrain.center
	wanted.clear()
	var origin := Vector2i(floori(terrain.focus.x / ROOT_SIZE), floori(terrain.focus.z / ROOT_SIZE))
	for z in range(-3, 4):
		for x in range(-3, 4):
			_select(Vector3i((origin.x + x) * ROOT_SIZE, (origin.y + z) * ROOT_SIZE, ROOT_SIZE))
	pending.clear()
	for key: Vector3i in wanted:
		if not patches.has(key):
			pending.append(key)
	pending.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return _distance(a) < _distance(b))

func _distance(key: Vector3i) -> float:
	var p := Vector2(terrain.focus.x, terrain.focus.z)
	var low := Vector2(key.x, key.y)
	return p.distance_to(p.clamp(low, low + Vector2.ONE * key.z))

func _select(key: Vector3i) -> void:
	if key.z > MIN_SIZE and _distance(key) < float(key.z) * 2.5:
		var half := key.z / 2
		for z in 2:
			for x in 2:
				_select(Vector3i(key.x + x * half, key.y + z * half, half))
	else:
		wanted[key] = true

func _build_patch(key: Vector3i) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var step := float(key.z) / CELLS
	for z in CELLS + 1:
		for x in CELLS + 1:
			var px := key.x + x * step
			var pz := key.y + z * step
			var h: float = terrain.raw_height(px, pz)
			vertices.append(Vector3(px, h, pz))
			var normal_step := maxf(2.0, step * 0.5)
			var dx: float = terrain.raw_height(px + normal_step, pz) - terrain.raw_height(px - normal_step, pz)
			var dz: float = terrain.raw_height(px, pz + normal_step) - terrain.raw_height(px, pz - normal_step)
			normals.append(Vector3(-dx, 2.0 * normal_step, -dz).normalized())
	for z in CELLS:
		for x in CELLS:
			var a := z * (CELLS + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + CELLS + 1, a + 1, a + CELLS + 2, a + CELLS + 1]))
	# Only the actual terrain casts shadows. Skirts are artificial vertical walls
	# used to hide LOD cracks, and must never darken the surrounding valleys.
	var shadow_arrays := []
	shadow_arrays.resize(Mesh.ARRAY_MAX)
	shadow_arrays[Mesh.ARRAY_VERTEX] = vertices.duplicate()
	shadow_arrays[Mesh.ARRAY_INDEX] = indices.duplicate()
	var terrain_shadow := ArrayMesh.new()
	terrain_shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shadow_arrays)
	# Skirts hide T-junctions where neighbouring patches have different LODs.
	for side in 4:
		for i in CELLS:
			var a := i
			var b := i + 1
			if side == 1:
				a = i * (CELLS + 1) + CELLS
				b = a + CELLS + 1
			elif side == 2:
				a = CELLS * (CELLS + 1) + i
				b = a + 1
			elif side == 3:
				a = i * (CELLS + 1)
				b = a + CELLS + 1
			var n := vertices.size()
			var depth := maxf(32.0, step * 0.5)
			vertices.append_array(PackedVector3Array([vertices[a], vertices[b], vertices[a] - Vector3.UP * depth, vertices[b] - Vector3.UP * depth]))
			normals.append_array(PackedVector3Array([normals[a], normals[b], normals[a], normals[b]]))
			indices.append_array(PackedInt32Array([n, n + 2, n + 1, n + 1, n + 2, n + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.shadow_mesh = terrain_shadow
	var surface := MeshInstance3D.new()
	surface.name = "Terrain_%d_%d_%dm" % [key.x, key.y, key.z]
	surface.mesh = mesh
	surface.material_override = terrain.material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	return surface
