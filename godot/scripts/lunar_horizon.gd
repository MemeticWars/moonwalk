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
var staged: Dictionary = {}

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
		staged[key] = _build_patch(key)
		staged[key].visible = false
		add_child(staged[key])
		# Empty areas can appear immediately. Only replacements must wait for
		# an atomic swap, otherwise coarse and fine surfaces overlap in flight.
		var replaces := false
		for existing: Vector3i in patches:
			if Rect2(key.x, key.y, key.z, key.z).intersects(Rect2(existing.x, existing.y, existing.z, existing.z)):
				replaces = true
				break
		if not replaces:
			patches[key] = staged[key]
			staged.erase(key)
	# Retire obsolete parents/children only after the replacement set is ready.
	if pending.is_empty():
		for key: Vector3i in patches.keys():
			if not wanted.has(key) or staged.has(key):
				patches[key].queue_free()
				patches.erase(key)
		patches.merge(staged, true)
		staged.clear()
	for key: Vector3i in patches:
		var covered: bool = key.z == MIN_SIZE and terrain.tiles.has(Vector2i(key.x / MIN_SIZE, key.y / MIN_SIZE))
		patches[key].visible = not covered

func _replan() -> void:
	last_center = terrain.center
	# Discard an unfinished staging set before planning another atomic swap.
	for key: Vector3i in staged:
		staged[key].queue_free()
	staged.clear()
	wanted.clear()
	var origin := Vector2i(floori(terrain.focus.x / ROOT_SIZE), floori(terrain.focus.z / ROOT_SIZE))
	for z in range(-3, 4):
		for x in range(-3, 4):
			_select(Vector3i((origin.x + x) * ROOT_SIZE, (origin.y + z) * ROOT_SIZE, ROOT_SIZE))
	pending.clear()
	for key: Vector3i in wanted:
		if not patches.has(key) or patches[key].get_meta("edge_steps", []) != _edge_steps(key):
			pending.append(key)
	pending.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return _distance(a) < _distance(b))

func _distance(key: Vector3i) -> float:
	var p := Vector2(terrain.focus.x, terrain.focus.z)
	var low := Vector2(key.x, key.y)
	return p.distance_to(p.clamp(low, low + Vector2.ONE * key.z))

func _select(key: Vector3i) -> void:
	var local_rect := Rect2(Vector2(terrain.center - Vector2i.ONE * terrain.FAR_RADIUS) * MIN_SIZE,
		Vector2.ONE * (2 * terrain.FAR_RADIUS + 1) * MIN_SIZE)
	var overlaps_local := local_rect.grow(MIN_SIZE).intersects(Rect2(key.x, key.y, key.z, key.z))
	if key.z > MIN_SIZE and (overlaps_local or _distance(key) < float(key.z) * 2.5):
		var half := key.z / 2
		for z in 2:
			for x in 2:
				_select(Vector3i(key.x + x * half, key.y + z * half, half))
	else:
		wanted[key] = true

func _edge_steps(key: Vector3i) -> PackedFloat32Array:
	var own_step := 2.0 if key.z == MIN_SIZE else float(key.z) / CELLS
	var result := PackedFloat32Array([own_step, own_step, own_step, own_step])
	var middle := Vector2(key.x, key.y) + Vector2.ONE * key.z * 0.5
	var probes := [Vector2(middle.x, key.y - 0.5), Vector2(key.x + key.z + 0.5, middle.y),
		Vector2(middle.x, key.y + key.z + 0.5), Vector2(key.x - 0.5, middle.y)]
	for neighbor: Vector3i in wanted:
		if neighbor.z <= key.z:
			continue
		for side in 4:
			if Rect2(neighbor.x, neighbor.y, neighbor.z, neighbor.z).has_point(probes[side]):
				result[side] = maxf(result[side], float(neighbor.z) / CELLS)
	return result

func _normal_at(x: float, z: float) -> Vector3:
	return Vector3(terrain.raw_height(x - 2.0, z) - terrain.raw_height(x + 2.0, z), 4.0,
		terrain.raw_height(x, z - 2.0) - terrain.raw_height(x, z + 2.0)).normalized()

func _build_patch(key: Vector3i) -> MeshInstance3D:
	# Match the walking mesh at its boundary, including intermediate vertices.
	var cells := 32 if key.z == MIN_SIZE else CELLS
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var step := float(key.z) / cells
	var edge_steps := _edge_steps(key)
	for z in cells + 1:
		for x in cells + 1:
			var px := key.x + x * step
			var pz := key.y + z * step
			var h: float = terrain.raw_height(px, pz)
			var normal := _normal_at(px, pz)
			# Snap intermediate fine-edge samples onto the actual coarse edge.
			# Shared corners already lie on both grids, so no skirt hides a gap.
			for side in 4:
				if not [z == 0, x == cells, z == cells, x == 0][side] or edge_steps[side] <= step:
					continue
				var horizontal := side == 0 or side == 2
				var along := px if horizontal else pz
				var low := floorf(along / edge_steps[side]) * edge_steps[side]
				var a := Vector2(low, pz) if horizontal else Vector2(px, low)
				var b := a + (Vector2.RIGHT if horizontal else Vector2.DOWN) * edge_steps[side]
				var t := (along - low) / edge_steps[side]
				h = lerpf(terrain.raw_height(a.x, a.y), terrain.raw_height(b.x, b.y), t)
				normal = _normal_at(a.x, a.y).lerp(_normal_at(b.x, b.y), t)
			vertices.append(Vector3(px, h, pz))
			normals.append(normal)
	for z in cells:
		for x in cells:
			var a := z * (cells + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + cells + 1, a + 1, a + cells + 2, a + cells + 1]))
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
		for i in cells:
			var a := i
			var b := i + 1
			if side == 1:
				a = i * (cells + 1) + cells
				b = a + cells + 1
			elif side == 2:
				a = cells * (cells + 1) + i
				b = a + 1
			elif side == 3:
				a = i * (cells + 1)
				b = a + cells + 1
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
	surface.set_meta("edge_steps", edge_steps)
	surface.name = "Terrain_%d_%d_%dm" % [key.x, key.y, key.z]
	surface.mesh = mesh
	surface.material_override = terrain.material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	return surface
