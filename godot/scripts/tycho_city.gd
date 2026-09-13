extends Node3D
## Full-detail source modules share resources; Godot generates mesh LODs.
## Only buildings in the active terrain tile neighbourhood are instantiated.
const Site := preload("res://scripts/tycho_site.gd")
const WaterLayout := preload("res://scripts/tycho_water_layout.gd")
const Cosmoport := preload("res://scripts/tycho_cosmoport.gd")
const Dome := preload("res://scripts/tycho_dome.gd")
const ASSETS := "res://assets/colonies/tycho/modules/"
const BEECH_BARK_AND_LEAVES := preload("res://shaders/foliage_silver.gdshader")
const GRASS_BLADE := preload("res://shaders/grass_blade.gdshader")
const GRASS_FIELD := preload("res://scripts/tycho_grass.gd")
const TOMATO_HEIGHT_M := 1.9017802476882935
const TOMATO_CLUSTER_SOURCE_HEIGHT_M := 0.5560800433158875
const BENCH_HEIGHT_SCALE := 0.72
const SEATED_AGNES_LIFT := 0.05
const BOOK_SCALE := 0.75
var terrain: Node3D
var descriptors: Array[Dictionary] = []
var loaded: Dictionary = {}
var scenes: Dictionary = {}
var requested: Dictionary = {}
var dimensions: Dictionary = {}
var ground_details: Node3D
## East annex site centres/sizes -- read by tycho_east_annex.gd (the extra
## dome shells + inter-dome tunnels + local solar array) and by _build_paths()
## below (D1's own dome needs matching cuts toward each connected site).
## Layout: m1 due east of D1, m2 due south, m3 due WEST (moved from north,
## its north slot now held by the solar array -- see tycho_east_annex.gd's
## SOLAR_SITE) -- each joined to D1 by its own tunnel. D2 sits further south,
## beyond m2, joined only to m2. West sits on a real, noticeably sloped
## shoulder of the peak (~55 m relief across the pad, more than D1's own
## ~50 m): the pad grading cuts into that slope rather than around it, so m3
## reads as dug into the hillside, with only part of its shell clear of it --
## intended, not a site-selection miss.
## Graph: m1-D1, m2-D1, m3-D1, m2-D2.
const M1_CENTER := Site.CENTER + Vector2(170.0, 0.0)
const M2_CENTER := Site.CENTER + Vector2(0.0, 170.0)
const M3_CENTER := Site.CENTER + Vector2(-170.0, 0.0)
const D2_CENTER := Site.CENTER + Vector2(0.0, 340.0)
const D2_RADIUS := 100.0
const D2_HEIGHT := 90.0
const MINI_RADIUS := 50.0
const MINI_HEIGHT := 45.0
const MINI_BLEND := 22.5
## Centre-to-centre spacing for every connected pair above was chosen as
## radius_a + TUNNEL_GAP + radius_b, so the tunnel exactly bridges the two
## shell surfaces with no gap and no overlap.
const TUNNEL_GAP := 20.0
## Airlock doorway size: matches the tunnel's own square passage
## (tycho_east_annex.gd's CROSS_SECTION_SIDE, ~6.86 m) plus a small margin,
## so the dome-wall opening clears the widened tunnel model on every side.
const TUNNEL_HALF_WIDTH := 3.6
const TUNNEL_CUT_HEIGHT := 7.2
## Park pond -> stream -> m3 fish pond (tycho_water_feature.gd). Kept here,
## alongside the other site constants, so _build_grass() below can carve
## matching keep-outs out of the lawn's MultiMesh grass.
const POND1_CENTER := WaterLayout.POND1_CENTER
const POND1_RADII := WaterLayout.POND1_RADII
## Rounded route and bed depths are shared with lunar_terrain.gd via WaterLayout.
const STREAM_WIDTH := WaterLayout.STREAM_WIDTH
const POND2_RADII := WaterLayout.POND2_RADII

## m1/m2/m3 sit due east/south/west of D1 -- exactly on the dome's own
## triangulation grid (multiples of TAU/Dome.SECTORS), same as the highway
## gate's angle. tycho_dome.gd removes a face by its CENTRE, which for the two
## faces straddling a grid line sits half a sector-width off that line; a cut
## arc narrower than that (as a physical-width-only asin() can easily be, once
## a big enough dome_radius shrinks the angle) removes neither straddling
## face, leaving their shared edge -- a beam running straight down the exact
## middle of the doorway. Floor the arc at a safe margin past that half-width
## so every cut clears its two straddling faces regardless of physical width.
static func tunnel_cut(from: Vector2, to: Vector2, radius: float) -> Dictionary:
	var min_clearance_arc := 0.65 * TAU / Dome.SECTORS
	return {"angle": atan2(to.y - from.y, to.x - from.x),
		"arc": maxf(asin(clampf(TUNNEL_HALF_WIDTH / radius, 0.0, 1.0)), min_clearance_arc), "cut_height": TUNNEL_CUT_HEIGHT}

static func tunnel_cuts_toward(from: Vector2, targets: Array, radius: float) -> Array[Dictionary]:
	var cuts: Array[Dictionary] = []
	for target: Vector2 in targets:
		cuts.append(tunnel_cut(from, target, radius))
	return cuts

func _ready() -> void:
	name = "TychoCity"
	dimensions = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "modules.json"))
	_layout()
	# Independent of the site descriptors above: it manages its own load/unload
	# distance against terrain.center, since it sits far outside TychoSite's
	# radius and must not be torn down when the dome/city itself unloads.
	var power_plant := preload("res://scripts/tycho_power_plant.gd").new()
	power_plant.terrain = terrain
	add_child(power_plant)
	# The east annex is an optional streamed extension while its separate
	# builder is present. Keep the base city runnable if that work is absent.
	var annex_script: Script = load("res://scripts/tycho_east_annex.gd") as Script
	if annex_script != null:
		var annex := annex_script.new() as Node3D
		annex.terrain = terrain
		add_child(annex)
	# Also optional/independent: the park pond -> stream -> m3 fish pond,
	# gated (in addition to its own distance check) on the east annex having
	# already graded m2's pad.
	var water_script: Script = load("res://scripts/tycho_water_feature.gd") as Script
	if water_script != null:
		var water := water_script.new() as Node3D
		water.terrain = terrain
		add_child(water)

func _place(kind: String, x: float, z: float, yaw: float = 0.0, y: float = 0.0, mirror: bool = false) -> void:
	var point := Site.CENTER + Vector2(x, z)
	descriptors.append({"kind": kind, "point": point, "yaw": yaw, "lift": y, "mirror": mirror,
		"asset": kind + "-mirrored" if mirror else kind,
		"tile": Vector2i(floori(point.x / 64.0), floori(point.y / 64.0))})

func _layout() -> void:
	# C-shaped neighbourhood, open to the south (-Z), around the inner park.
	_place("central-house", 0, 35)
	_place("central-building", 69, -20)
	for side in [-1.0, 1.0]:
		var towers: Array[Vector2] = [Vector2(side * 34, 58), Vector2(side * 56, 38), Vector2(side * 68, 10)]
		for tower: Vector2 in towers:
			_place("block-of-flats", tower.x, tower.y)
		for i in 2:
			var center := (towers[i] + towers[i + 1]) * 0.5
			var direction := towers[i + 1] - towers[i]
			var lift := float(dimensions["block-of-flats"].size_m[1]) * 2.0 / 3.0 - float(dimensions["link-between-block-of-flats"].size_m[1]) * 0.5
			_place("link-between-block-of-flats", center.x, center.y, atan2(-direction.y, direction.x), lift)
			descriptors[-1]["span"] = direction.length() - float(dimensions["block-of-flats"].size_m[0]) * 0.8
	for z in [-22.0, 0.0, 22.0]:
		_place("twin-houses", -39, z, PI / 2)
	_place("twin-houses", 43, 0, -PI / 2)
	_place("l-shape-building", -52, -44)
	_place("l-shape-building", 52, -44, 0, 0, true)
	# Eastern agricultural quarter, opposite the west tree garden.
	_place("greenhouse", 23, -55, 0)
	_place("greenhouse", 23, -47, 0)
	_place("greenhouse", 23, -39, 0)
	# Solar arrays moved off the dome floor entirely: see TychoPowerPlant, added
	# below as a permanent sibling of this node's own descriptor-driven city.
	for z in [-28.0, -16.0, -4.0]:
		_place("tank", -77, z, PI / 2.0)
	# Benches line both verges of the main north-south road, clear of crossings.
	_place("bench", -7.0, -24.0, PI / 2.0)
	descriptors[-1]["seated_agnes"] = true
	_place("bench", 7.0, -24.0, -PI / 2.0)
	_place("radio-mast", -83, 12)
	_place("radio-mast", 83, 12)
	_place("radio-mast", 0, 78)
	# A dense west garden; the east lawn stays completely open for future glasshouses.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4311
	var size_rng := RandomNumberGenerator.new()
	size_rng.seed = 88411
	# The beech atlas contains orange leaves and grey-blue trunk islands in one
	# material. The shader separates them by their source colour: silver bark,
	# green leaves. Birch leaves
	# are already green in the atlas -> nudge each tree to a different green while
	# the white bark stays near-white.
	var beech_bark_silver := [Color("cdd2da"), Color("c1c7d1"), Color("d7dbe1"), Color("b7bfcb")]
	var beech_leaf_green := [Color("4f7e32"), Color("5d9139"), Color("47762e"), Color("6d9c42")]
	var birch_green := [Color(0.86, 0.97, 0.80), Color(0.92, 1.0, 0.86), Color(0.79, 0.91, 0.72), Color(0.95, 1.0, 0.92), Color(0.83, 0.94, 0.77)]
	var birch_index := 0
	var column := 0
	for x in [-11.0, -16.0, -21.0, -26.0]:
		var row := 0
		for z in [-76.0, -68.0, -60.0, -52.0, -44.0, -36.0, -28.0, -20.0, -12.0]:
			# Birches form the exposed north-west outer edge. Pine and beech then
			# occupy two compact interior groves instead of alternating tree-by-tree.
			var kind := "park-beech"
			if column == 3 or (row == 0 and column < 3):
				kind = "park-birch" # 9 west-edge + 3 north-edge = 12
			elif row >= 1 and row <= 6 and (column == 1 or column == 2):
				kind = "park-pine" # central 2 x 6 grove
			_place(kind, x + rng.randf_range(-0.8, 0.8), z + rng.randf_range(-1.1, 1.1), rng.randf() * TAU)
			# Natural, bounded size distribution: sigma 15% around each species'
			# authored Tycho scale, without extreme outliers clipping the dome.
			descriptors[-1]["tree_scale"] = clampf(size_rng.randfn(1.0, 0.15), 0.70, 1.30)
			if kind == "park-beech":
				var beech_shade := (row + column) % beech_bark_silver.size()
				descriptors[-1]["beech_bark_silver"] = beech_bark_silver[beech_shade]
				descriptors[-1]["beech_leaf_green"] = beech_leaf_green[beech_shade]
			elif kind == "park-birch":
				descriptors[-1]["foliage_tint"] = birch_green[birch_index % birch_green.size()]
				birch_index += 1
			row += 1
		column += 1

func _process(_delta: float) -> void:
	var wanted: Dictionary = {}
	for i in descriptors.size():
		var tile: Vector2i = descriptors[i].tile
		var distance := maxi(absi(tile.x - terrain.center.x), absi(tile.y - terrain.center.y))
		if distance <= terrain.FAR_RADIUS:
			wanted[i] = distance <= terrain.NEAR_RADIUS
	for i in loaded.keys():
		if not wanted.has(i):
			loaded[i].queue_free()
			loaded.erase(i)
	if wanted.is_empty():
		scenes.clear()
		facade_shapes.clear()
		if is_instance_valid(ground_details):
			ground_details.queue_free()
			ground_details = null
	else:
		if not is_instance_valid(ground_details):
			_build_paths()
	# Drain completed requests even after leaving the site, releasing resources.
	for kind: String in requested.keys():
		var path := ASSETS + kind + ".glb"
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var scene := ResourceLoader.load_threaded_get(path) as PackedScene
			if not wanted.is_empty():
				scenes[kind] = scene
			requested.erase(kind)
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			push_error("Cannot load Tycho module: " + path)
			requested.erase(kind)
	var built := false
	for i in wanted:
		if loaded.has(i):
			# The Body may hold one shape (a plain box, or a fitted prism/cylinder)
			# or several (the L-shape's Wing + Leg boxes) -- toggle every child.
			for collider: CollisionShape3D in (loaded[i].get_node("Body") as StaticBody3D).get_children():
				if collider.disabled == wanted[i]:
					collider.set_deferred("disabled", not wanted[i])
			var climb_surface := loaded[i].get_node_or_null("ClimbSurface") as StaticBody3D
			if climb_surface != null:
				for climb_collider: CollisionShape3D in climb_surface.get_children():
					if climb_collider.disabled == wanted[i]:
						climb_collider.set_deferred("disabled", not wanted[i])
			continue
		var kind: String = descriptors[i].asset
		if not scenes.has(kind):
			if not requested.has(kind):
				ResourceLoader.load_threaded_request(ASSETS + kind + ".glb", "PackedScene")
				requested[kind] = true
		elif not built:
			_build_module(i, wanted[i])
			built = true

const CLIMBABLE_KINDS := ["central-house", "central-building", "block-of-flats", "twin-houses", "l-shape-building"]
var facade_shapes: Dictionary = {}

func _build_module(index: int, collision_enabled: bool) -> void:
	var descriptor := descriptors[index]
	var kind: String = descriptor.kind
	var root := Node3D.new()
	root.name = kind + "_%02d" % index
	add_child(root)
	root.position = Vector3(descriptor.point.x, terrain.city_level + descriptor.lift, descriptor.point.y)
	root.rotation.y = descriptor.yaw
	var visual := (scenes[descriptor.asset] as PackedScene).instantiate() as Node3D
	root.add_child(visual)
	if kind.begins_with("park-"):
		visual.scale *= float(descriptor.get("tree_scale", 1.0))
	if kind == "block-of-flats":
		visual.scale *= 1.2
	if kind == "bench":
		# The source seat is unusually tall for Agnes's 1.7 m seated model.
		# Lower the whole frame while keeping its width and seat depth intact.
		visual.scale.y = BENCH_HEIGHT_SCALE
	if kind == "greenhouse":
		# The normalized source is 24 m wide; the Tycho greenhouse uses a 12 m bay.
		visual.scale.x = 0.5
	if descriptor.has("span"):
		visual.scale.x = descriptor.span / float(dimensions[kind].size_m[0])
	if kind in CLIMBABLE_KINDS:
		_add_climb_surface(root, visual, collision_enabled)
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if kind == "park-pine":
			_apply_pine_materials(mesh)
		if descriptor.has("foliage_tint") or descriptor.has("beech_bark_silver"):
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface)
				if source is not StandardMaterial3D:
					continue
				if descriptor.has("beech_bark_silver"):
					var beech_material := ShaderMaterial.new()
					beech_material.shader = BEECH_BARK_AND_LEAVES
					beech_material.set_shader_parameter("albedo_tex", (source as StandardMaterial3D).albedo_texture)
					beech_material.set_shader_parameter("normal_tex", (source as StandardMaterial3D).normal_texture)
					beech_material.set_shader_parameter("use_normal", (source as StandardMaterial3D).normal_texture != null)
					beech_material.set_shader_parameter("bark_silver", descriptor.beech_bark_silver)
					beech_material.set_shader_parameter("leaf_green", descriptor.beech_leaf_green)
					mesh.set_surface_override_material(surface, beech_material)
				else:
					var foliage := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
					foliage.albedo_color = descriptor.foliage_tint
					# A faint tint-coloured glow keeps the greens legible under the
					# low sun without washing out the white bark.
					foliage.emission_enabled = true
					foliage.emission_texture = null
					foliage.emission = descriptor.foliage_tint
					foliage.emission_energy_multiplier = 0.12
					mesh.set_surface_override_material(surface, foliage)
		mesh.visibility_range_end = 480.0
		mesh.lod_bias = 1.5
	if kind == "greenhouse":
		_add_greenhouse_film(root, visual)
	if descriptor.get("seated_agnes", false):
		var resident := load(ASSETS + "agnes-seated.glb").instantiate() as Node3D
		resident.name = "SeatedAgnes"
		# The prepared scene origin is the seat contact point.
		resident.scale = Vector3.ONE
		var seating: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "seating.json"))
		# Lift the posed model just clear of the paving: one boot reaches below the
		# source seat origin once the bench is shortened.
		resident.position.y = float(seating.seat_height) * BENCH_HEIGHT_SCALE + 0.005 + SEATED_AGNES_LIFT
		root.add_child(resident)
		var book := load(ASSETS + "voyages-extraordinaires.glb").instantiate() as Node3D
		book.name = "VoyagesExtraordinaires"
		# The book's pivot is central. Its lower cover now rests across the thighs
		# rather than floating above Agnes's lap.
		book.position = Vector3(0.0, 0.26, 0.30)
		# Flip the lying book over its longitudinal axis so its cover faces up.
		book.rotation_degrees = Vector3(258.0, 0.0, 0.0)
		book.scale = Vector3.ONE * BOOK_SCALE
		resident.add_child(book)
		for mesh: MeshInstance3D in book.find_children("*", "MeshInstance3D", true, false):
			mesh.visibility_range_end = 120.0
		for player: AnimationPlayer in resident.find_children("*", "AnimationPlayer", true, false):
			for clip in player.get_animation_list():
				if clip != "RESET":
					player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
					player.play(clip)
					player.advance(0.0)
					break
	var body := StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	var size: Array = dimensions[kind].size_m
	if kind in CLIMBABLE_KINDS:
		# ClimbSurface now supplies movement AND probe collision. A full-height
		# footprint prism fills roof recesses and can block the capsule in midair.
		# Keep the empty Body node for the common streaming lifecycle.
		body.collision_layer = 0
	else:
		var collider := CollisionShape3D.new()
		collider.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(size[0], size[1], size[2])
		if descriptor.has("span"):
			box.size.x = descriptor.span
		# Simple exterior collision keeps the render geometry out of the physics mesh.
		if kind == "link-between-block-of-flats":
			box.size.y = 2.0
			collider.position.y = float(size[1]) - 2.0
		elif kind == "radio-mast":
			box.size.x = 1.2
			box.size.z = 1.2
		elif kind == "bench":
			box.size.y *= BENCH_HEIGHT_SCALE
		elif kind.begins_with("park-"):
			box.size = Vector3(0.32, 4.0, 0.32)
			box.size *= float(descriptor.get("tree_scale", 1.0))
		collider.position.y += box.size.y * 0.5
		collider.shape = box
		collider.disabled = not collision_enabled
		body.add_child(collider)
	loaded[index] = root

## Footprint-fitted movement collision for the towers whose silhouette a plain
## bounding box badly overshoots. Points come from a one-off top-down raycast
## probe against each asset's real mesh (tools/… not kept; see index/characters.md), not
## from any authored blueprint, so they are an approximation, not exact metres.
## GDScript can't fold a PackedVector2Array(...) constructor call into a const,
## so these stay plain Arrays of Vector2 -- fine, _add_prism_collider only
## ever iterates them once per building instance.
const OCTAGON_FOOTPRINT := [
	Vector2(7.5, 0.0), Vector2(5.75, 2.5), Vector2(5.3, 5.3), Vector2(2.4, 5.75),
	Vector2(0.0, 7.75), Vector2(-2.4, 5.75), Vector2(-5.3, 5.3), Vector2(-5.75, 2.5),
	Vector2(-7.5, 0.0), Vector2(-5.75, -2.5), Vector2(-5.3, -5.3), Vector2(-2.4, -5.75),
	Vector2(0.0, -7.75), Vector2(2.4, -5.75), Vector2(5.3, -5.3), Vector2(5.75, -2.5),
]
const CENTRAL_BUILDING_FOOTPRINT := [
	Vector2(15.7, 0.0), Vector2(13.0, 5.9), Vector2(8.8, 10.0), Vector2(3.3, 11.0),
	Vector2(-1.2, 12.0), Vector2(-5.9, 11.3), Vector2(-11.8, 10.6), Vector2(-15.5, 5.9),
	Vector2(-15.7, 0.0), Vector2(-15.7, -6.0), Vector2(-11.8, -10.6), Vector2(-6.0, -11.5),
	Vector2(-1.2, -12.0), Vector2(3.3, -11.0), Vector2(8.1, -9.3), Vector2(13.0, -5.9),
]

func _add_precise_footprint_collider(body: StaticBody3D, descriptor: Dictionary, kind: String, size: Array, enabled: bool) -> void:
	match kind:
		"l-shape-building":
			# Two rectangles: a full-width wing plus a narrower leg on one side
			# (mirrored to the other side for the "-mirrored" placements).
			var height: float = size[1]
			var leg_x := -8.25 if descriptor.mirror else 8.25
			_add_box_collider(body, "Wing", Vector3(0.0, 0.0, -6.5), Vector3(23.0, height, 10.0), enabled)
			_add_box_collider(body, "Leg", Vector3(leg_x, 0.0, 4.25), Vector3(6.5, height, 12.5), enabled)
		"block-of-flats":
			_add_prism_collider(body, "Shape", OCTAGON_FOOTPRINT, size[1], enabled)
		"central-building":
			# Same "mast has no giant invisible wall" height cut the old box used.
			_add_prism_collider(body, "Shape", CENTRAL_BUILDING_FOOTPRINT, 8.0, enabled)
		"central-house":
			# This one really is a ~50 m rotunda, not an import-scale bug (its
			# footprint radius holds within 25.0-25.25 m at all 16 sampled angles).
			_add_cylinder_collider(body, "Shape", 24.5, 8.0, enabled)

func _add_box_collider(body: StaticBody3D, shape_name: String, center: Vector3, box_size: Vector3, enabled: bool) -> void:
	var collider := CollisionShape3D.new()
	collider.name = shape_name
	var box := BoxShape3D.new()
	box.size = box_size
	collider.shape = box
	collider.position = center + Vector3(0.0, box_size.y * 0.5, 0.0)
	collider.disabled = not enabled
	body.add_child(collider)

func _add_prism_collider(body: StaticBody3D, shape_name: String, footprint: Array, height: float, enabled: bool) -> void:
	var collider := CollisionShape3D.new()
	collider.name = shape_name
	var points := PackedVector3Array()
	for p in footprint:
		points.append(Vector3(p.x, 0.0, p.y))
		points.append(Vector3(p.x, height, p.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collider.shape = shape
	collider.disabled = not enabled
	body.add_child(collider)

func _add_cylinder_collider(body: StaticBody3D, shape_name: String, radius: float, height: float, enabled: bool) -> void:
	var collider := CollisionShape3D.new()
	collider.name = shape_name
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collider.shape = shape
	collider.position.y = height * 0.5
	collider.disabled = not enabled
	body.add_child(collider)

func _add_climb_surface(root: Node3D, visual: Node3D, enabled: bool) -> void:
	# One surface for walking (layer 1) and climbing probes (layer 2), including
	# curved roofs, door openings and mirrored/scaled module instances.
	var body := StaticBody3D.new()
	body.name = "ClimbSurface"
	body.collision_layer = 3
	body.collision_mask = 0
	root.add_child(body)
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.mesh.get_surface_count() == 0: continue
		var collider := CollisionShape3D.new()
		if not facade_shapes.has(mesh.mesh):
			facade_shapes[mesh.mesh] = mesh.mesh.create_trimesh_shape()
		collider.shape = facade_shapes[mesh.mesh]
		collider.disabled = not enabled
		# The collider is a child of the module root, so retain every nested mesh
		# transform (including rotations and authored source scale).
		collider.transform = body.global_transform.affine_inverse() * mesh.global_transform
		body.add_child(collider)

func _apply_pine_materials(mesh: MeshInstance3D) -> void:
	# Pine GLB already exposes separate Trunk and Leaves meshes. Keep that split:
	# bark/branches read as wood, while needles retain their own green material.
	var is_trunk := mesh.name.to_lower().contains("trunk")
	var tint := Color("69452c") if is_trunk else Color("356f32")
	for surface in mesh.mesh.get_surface_count():
		var source := mesh.get_active_material(surface)
		var material: StandardMaterial3D
		if source is StandardMaterial3D:
			material = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			material = StandardMaterial3D.new()
		material.albedo_color = tint
		material.metallic = 0.0
		material.roughness = 0.82 if is_trunk else 0.70
		if not is_trunk:
			material.emission_enabled = true
			material.emission = tint
			material.emission_energy_multiplier = 0.08
		mesh.set_surface_override_material(surface, material)

func _add_greenhouse_film(root: Node3D, visual: Node3D) -> void:
	# The source greenhouse is a groin vault: two half-cylinder tunnels that cross
	# at the centre (a long bay along X, a short wide bay along Z). Read the real
	# mesh, recover each tunnel's own arch profile, and skin the two separately so
	# the film sits on each half-cylinder instead of one guessed shell.
	var raw := PackedVector3Array()
	for m: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		raw = m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		break
	var x_scale: float = visual.scale.x  # only X is rescaled for the Tycho bay

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.albedo_color = Color(0.62, 0.88, 0.92, 0.17)
	material.metallic = 0.0
	material.roughness = 0.08
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	surface.set_material(material)

	var axis_x := 0.0
	var axis_z := 0.0
	for v in raw:
		axis_x = maxf(axis_x, absf(v.x))
		axis_z = maxf(axis_z, absf(v.z))
	# Long tunnel runs along X: sample its arch (over Z) only from the far ends,
	# where the crossing tunnel is absent. Then loft it along the full X length.
	_loft_vault(surface, _vault_profile(raw, true, x_scale, axis_x, axis_z), true, axis_x * x_scale)
	# Short tunnel runs along Z: sample its arch (over X) from the far ends in Z.
	_loft_vault(surface, _vault_profile(raw, false, x_scale, axis_x, axis_z), false, axis_z)

	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "TransparentFilm"
	node.mesh = surface.commit()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	_add_greenhouse_crops(root)

## Recover one tunnel's arch cross-section. `along_x` picks the long tunnel
## (profile over Z, sampled where |x| is large) or the short one (profile over X,
## sampled where |z| is large). Returns (transverse, height) points in the final
## scaled frame, ordered across the span.
func _vault_profile(raw: PackedVector3Array, along_x: bool, x_scale: float, axis_x: float, axis_z: float) -> PackedVector2Array:
	var bins := 48
	var axis_extent := axis_x if along_x else axis_z
	var tr_extent := axis_z if along_x else axis_x
	var ys := PackedFloat32Array()
	ys.resize(bins + 1)
	ys.fill(0.0)
	for v in raw:
		var axis_c := absf(v.x) if along_x else absf(v.z)
		if axis_c < 0.72 * axis_extent:
			continue  # skip the centre so the crossing tunnel doesn't bleed in
		var tr := v.z if along_x else v.x
		var t := tr / tr_extent * 0.5 + 0.5
		if t < 0.0 or t > 1.0:
			continue
		var idx := clampi(roundi(t * bins), 0, bins)
		ys[idx] = maxf(ys[idx], v.y)
	var pts := PackedVector2Array()
	var half := tr_extent if along_x else tr_extent * x_scale
	for i in bins + 1:
		var u := -half + 2.0 * half * float(i) / float(bins)
		pts.append(Vector2(u, ys[i]))
	return pts

## Skin a tunnel: sweep its arch profile along its axis and cap both ends. The
## flat run of the profile where the arch has already met the ground is skipped.
func _loft_vault(surface: SurfaceTool, profile: PackedVector2Array, along_x: bool, half_length: float) -> void:
	for i in range(1, profile.size()):
		var p0 := profile[i - 1]
		var p1 := profile[i]
		if p0.y < 0.06 and p1.y < 0.06:
			continue
		if along_x:
			_add_quad(surface,
				Vector3(-half_length, p0.y, p0.x), Vector3(half_length, p0.y, p0.x),
				Vector3(half_length, p1.y, p1.x), Vector3(-half_length, p1.y, p1.x))
		else:
			_add_quad(surface,
				Vector3(p0.x, p0.y, -half_length), Vector3(p0.x, p0.y, half_length),
				Vector3(p1.x, p1.y, half_length), Vector3(p1.x, p1.y, -half_length))
	for s in [-1.0, 1.0]:
		var centre := Vector3(s * half_length, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, s * half_length)
		for i in range(1, profile.size()):
			var p0 := profile[i - 1]
			var p1 := profile[i]
			if p0.y < 0.06 and p1.y < 0.06:
				continue
			var r0 := Vector3(s * half_length, p0.y, p0.x) if along_x else Vector3(p0.x, p0.y, s * half_length)
			var r1 := Vector3(s * half_length, p1.y, p1.x) if along_x else Vector3(p1.x, p1.y, s * half_length)
			surface.add_vertex(centre)
			surface.add_vertex(r0)
			surface.add_vertex(r1)

func _add_greenhouse_crops(root: Node3D) -> void:
	var tomato := preload("res://assets/colonies/tycho/modules/tomato.glb")
	var tomatoes := preload("res://assets/colonies/tycho/modules/tomatoes.glb")
	# Centre the tomato cluster; single plants sit on the two short transverse arms.
	_add_crop_model(root, tomatoes, Vector3(0.0, 0.05, 0.0), 0.0, TOMATO_HEIGHT_M / TOMATO_CLUSTER_SOURCE_HEIGHT_M)
	_add_crop_model(root, tomato, Vector3(0.0, 0.05, -2.15), PI * 0.5)
	_add_crop_model(root, tomato, Vector3(0.0, 0.05, 2.15), PI * 0.5)
	_add_crop_model(root, tomato, Vector3(-5.0, 0.05, 0.0), 0.0)
	_add_crop_model(root, tomato, Vector3(5.0, 0.05, 0.0), PI)


func _add_crop_model(root: Node3D, scene: PackedScene, local_position: Vector3, yaw: float, height_scale: float = 1.0) -> void:
	var model := scene.instantiate() as Node3D
	model.name = "TomatoCropModel_%02d" % root.get_child_count()
	model.position = local_position
	model.rotation.y = yaw
	# Keep the crop-bed proportions intact: height matching also enlarges X/Z.
	model.scale = Vector3.ONE * height_scale
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 260.0
	root.add_child(model)

func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(d)

func _build_paths() -> void:
	ground_details = Node3D.new()
	ground_details.name = "CityPaths"
	add_child(ground_details)
	# Highway gate: due north (-Z), exactly on the dome's triangulation grid so the
	# angular cut lands on whole sectors (no stray partial-triangle beams left
	# standing in the opening), and its passage axis lands on x=0 -- the same
	# central axis as the main north-south road's Rect2(-5, -97, 10, 114) below.
	# Same opening serves the cosmoport road.
	const GATE_DIR := Vector2(0.0, -1.0)
	# The actual baked highway heading (road_streamer's `direction`, bearing 12.94deg,
	# fixed by the real colonies.json bearing to InPost Central, independent of
	# where the dome itself sits) and its centreline origin -- Site.CENTER plus
	# the same fixed dome-to-anchor offset road_streamer.town_square_origin()
	# uses for Tycho -- for the cosmoport off-ramp to branch off the real
	# carriageway rather than a guessed line.
	const HIGHWAY_DIR := Vector2(0.2239, -0.9746)
	var dome := preload("res://scripts/tycho_dome.gd").new()
	dome.position = Vector3(Site.CENTER.x, terrain.city_level, Site.CENTER.y)
	dome.gate_angle = atan2(GATE_DIR.y, GATE_DIR.x)
	dome.gate_arc = 0.1
	# Airlock tunnels toward the east annex's three mini-domes (m1/m2/m3): see
	# tycho_east_annex.gd, which cuts the matching opening on their side.
	dome.extra_cuts = tunnel_cuts_toward(Site.CENTER, [M1_CENTER, M2_CENTER, M3_CENTER], D2_RADIUS)
	ground_details.add_child(dome)
	# Real terrain climbs steeply just past D1's own flattened pad on the gate
	# side -- expected, this whole site sits on the central peak's shoulder --
	# so without their own graded pads the gate/forecourt/junction and the
	# cosmoport apron would be half-buried in that slope, same as an
	# ungraded east-annex mini-dome would be (see tycho_east_annex.gd's own
	# add_city_pad calls). Register both BEFORE building the cosmoport node,
	# which samples this same ground in its own _ready().
	var hwy_dir := HIGHWAY_DIR.normalized()
	var hwy_side := Vector2(-hwy_dir.y, hwy_dir.x)
	var highway_anchor: Vector2 = Site.HIGHWAY_ANCHOR_OFFSET
	var gate_cluster: Array[Vector2] = [
		highway_anchor + GATE_DIR * 100.0,              # dome gate
		highway_anchor + hwy_dir * 64.0 + GATE_DIR * 5.0,  # forecourt
		highway_anchor + hwy_dir * 150.0,               # motorway start / ground_pin
		highway_anchor + hwy_dir * 175.0,               # rail-free junction
	]
	var gate_centroid := Vector2.ZERO
	for p: Vector2 in gate_cluster:
		gate_centroid += p
	gate_centroid /= gate_cluster.size()
	var gate_radius := 0.0
	for p: Vector2 in gate_cluster:
		gate_radius = maxf(gate_radius, p.distance_to(gate_centroid))
	terrain.add_city_pad(Site.CENTER + gate_centroid, gate_radius + 15.0, 40.0, 80.0, terrain.city_level)
	var apron_center := highway_anchor + hwy_dir * 150.0 + hwy_side * 95.0
	terrain.add_city_pad(Site.CENTER + apron_center, Cosmoport.APRON_RADIUS + 18.0, 35.0, 80.0, terrain.city_level)
	var cosmoport := Cosmoport.new()
	cosmoport.terrain = terrain
	cosmoport.gate_dir = GATE_DIR
	cosmoport.highway_dir = HIGHWAY_DIR
	cosmoport.highway_origin = Site.HIGHWAY_ANCHOR_OFFSET
	cosmoport.position = Vector3(Site.CENTER.x, terrain.city_level, Site.CENTER.y)
	ground_details.add_child(cosmoport)
	var lamps := preload("res://scripts/tycho_city_lamps.gd").new()
	lamps.position = Vector3(Site.CENTER.x, terrain.city_level, Site.CENTER.y)
	ground_details.add_child(lamps)
	var mist := preload("res://scripts/tycho_low_mist.gd").new()
	mist.position = Vector3(Site.CENTER.x, terrain.city_level, Site.CENTER.y)
	ground_details.add_child(mist)
	var clouds := preload("res://scripts/tycho_clouds.gd").new()
	ground_details.add_child(clouds)
	var weather := preload("res://scripts/tycho_weather.gd").new()
	weather.terrain = terrain
	weather.position = Vector3(Site.CENTER.x, terrain.city_level, Site.CENTER.y)
	ground_details.add_child(weather)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("74777a")
	concrete.roughness = 0.95
	# The central road (plaza + N-S spine + two service lanes) stays paved; grass
	# and a green ground cover the rest of the pad.
	var roads: Array[Rect2] = [
		Rect2(-5.0, -97.0, 10.0, 114.0),
		Rect2(-35.0, 0.5, 70.0, 7.0),
		Rect2(-32.5, -37.0, 5.0, 66.0),
		Rect2(27.5, -37.0, 5.0, 66.0),
	]
	for r: Rect2 in roads:
		_path(r.position + r.size * 0.5, r.size, concrete)
	_add_city_lawn()
	_build_grass(roads)
	var fox := preload("res://scripts/fox.gd").new()
	fox.terrain = terrain
	ground_details.add_child(fox)

## A green ground disc across the whole flattened pad, under the grass so the
## gaps between blades read green instead of regolith. Roads draw on top of it.
func _add_city_lawn() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	# Match the ground's world-aligned grid and refined channel cells. A flat
	# fan across the park used to seal the excavated basin visually.
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for z in range(floori((Site.CENTER.y-93)/2), ceili((Site.CENTER.y+93)/2)):
		for x in range(floori((Site.CENTER.x-93)/2), ceili((Site.CENTER.x+93)/2)):
			var origin := Vector2(x,z)*2.0
			if (origin + Vector2.ONE - Site.CENTER).length() > 92.0:
				continue
			var step := WaterLayout.cell_step(origin + Vector2.ONE)
			var n := roundi(2.0/step)
			var base := vertices.size()
			for j in n+1:
				for i in n+1:
					var p := origin + Vector2(i,j)*step
					var h: float = terrain._ground_vertex_height(p.x,p.y,step)
					vertices.append(Vector3(p.x-Site.CENTER.x,h-terrain.city_level+0.015,p.y-Site.CENTER.y))
					colors.append(Color("65584a") if WaterLayout.depth(p) > 0.01 else Color("35502c"))
			for j in n:
				for i in n:
					var v := base+j*(n+1)+i
					indices.append_array(PackedInt32Array([v,v+1,v+n+1,v+1,v+n+2,v+n+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh,0)
	st.generate_normals()
	var disc := MeshInstance3D.new()
	disc.name = "CityLawn"
	disc.mesh = st.commit()
	disc.material_override = mat
	disc.position = Vector3(Site.CENTER.x, terrain.city_level, Site.CENTER.y)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_details.add_child(disc)
	# The existing service lane crosses the brook at x=-30, z=-11.
	# A real deck collider keeps pedestrians above the narrow channel.
	var bridge := StaticBody3D.new()
	bridge.name = "BrookFootbridge"
	bridge.position = Vector3(Site.CENTER.x-30, terrain.city_level, Site.CENTER.y-11)
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.0, 0.10, 1.4)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	bridge.add_child(collision)
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = shape.size
	deck.mesh = deck_mesh
	var deck_material := StandardMaterial3D.new()
	deck_material.albedo_color = Color("74777a")
	deck.material_override = deck_material
	bridge.add_child(deck)
	ground_details.add_child(bridge)

func _build_grass(roads: Array) -> void:
	# One blade = a 2 cm wide quad. Per-instance custom data carries heading, wind
	# phase, height (~N(0.40, 0.10) m) and a shade jitter; the shader stretches the
	# quad to that height, tints shorter blades lighter, bends blades (idle breeze
	# + a wobble trailing Agnes) and keeps the transform translation-only. Blades
	# fill a jittered grid over the whole pad, minus the paved roads, the park
	# trees and every structure footprint. One MultiMesh -> a single draw call.
	var blade := QuadMesh.new()
	blade.size = Vector2(0.02, 0.4)  # 0.4 = reference height; the shader rescales per blade
	blade.center_offset = Vector3(0.0, 0.2, 0.0)  # stand on the ground, not through it
	var grass := ShaderMaterial.new()
	grass.shader = GRASS_BLADE
	grass.set_shader_parameter("emission_amount", 0.5)
	blade.material = grass

	# Keep-outs, in pad-local coordinates (relative to Site.CENTER).
	var trees: PackedVector2Array = PackedVector2Array()
	var box_c: PackedVector2Array = PackedVector2Array()  # footprint centre
	var box_h: PackedVector2Array = PackedVector2Array()  # footprint half-extents (already margined)
	var box_cos: PackedFloat32Array = PackedFloat32Array()
	var box_sin: PackedFloat32Array = PackedFloat32Array()
	for d: Dictionary in descriptors:
		var k := String(d.kind)
		var local: Vector2 = d.point - Site.CENTER
		if k.begins_with("park-"):
			trees.append(local)
			continue
		var sx := 2.0
		var sz := 2.0
		if dimensions.has(k):
			sx = float(dimensions[k].size_m[0])
			sz = float(dimensions[k].size_m[2])
		if d.has("span"):
			sx = float(d.span)
		if k == "greenhouse":
			sx *= 0.5  # matches visual.scale.x
		box_c.append(local)
		box_h.append(Vector2(sx * 0.5 + 0.6, sz * 0.5 + 0.6))
		box_cos.append(cos(-float(d.yaw)))
		box_sin.append(sin(-float(d.yaw)))
	# The park pond and the stream feeding it (tycho_water_feature.gd) also
	# need to keep grass blades from growing straight through the water.
	box_c.append(POND1_CENTER - Site.CENTER)
	box_h.append(POND1_RADII + Vector2(0.6, 0.6))
	box_cos.append(1.0)
	box_sin.append(0.0)
	const STREAM_CLEARANCE := STREAM_WIDTH * 0.5 + 0.6

	var grown_roads: Array[Rect2] = []
	for r: Rect2 in roads:
		grown_roads.append(r.grow(0.4))

	var rng := RandomNumberGenerator.new()
	rng.seed = 74071
	const SPACING := 0.22
	const TREE_CLEARANCE_SQ := 2.5 * 2.5
	const PAD_R := 91.0
	const PAD_R_SQ := PAD_R * PAD_R
	var places: Array[Vector3] = []
	var customs: Array[Color] = []  # (heading, wind phase, blade height m, shade jitter)
	var steps := int(PAD_R * 2.0 / SPACING)
	for ix in steps:
		for iz in steps:
			var lx := -PAD_R + (float(ix) + 0.5 + rng.randf_range(-0.45, 0.45)) * SPACING
			var lz := -PAD_R + (float(iz) + 0.5 + rng.randf_range(-0.45, 0.45)) * SPACING
			var here := Vector2(lx, lz)
			if here.length_squared() > PAD_R_SQ:
				continue
			var blocked := false
			for r: Rect2 in grown_roads:
				if r.has_point(here):
					blocked = true
					break
			if blocked:
				continue
			for t: Vector2 in trees:
				if here.distance_squared_to(t) < TREE_CLEARANCE_SQ:
					blocked = true
					break
			if blocked:
				continue
			for b in box_c.size():
				var dx := lx - box_c[b].x
				var dz := lz - box_c[b].y
				var rx := dx * box_cos[b] - dz * box_sin[b]
				var rz := dx * box_sin[b] + dz * box_cos[b]
				if absf(rx) <= box_h[b].x and absf(rz) <= box_h[b].y:
					blocked = true
					break
			if blocked:
				continue
			if WaterLayout.stream_distance(here + Site.CENTER) < STREAM_CLEARANCE:
				blocked = true
			if blocked:
				continue
			places.append(Vector3(lx, 0.02, lz))
			var height := clampf(rng.randfn(0.40, 0.10), 0.16, 0.72)
			customs.append(Color(rng.randf() * TAU, rng.randf() * TAU, height, rng.randf()))

	var field := GRASS_FIELD.new()
	field.name = "LawnGrass"
	field.terrain = terrain
	field.material = grass
	field.position = Vector3(Site.CENTER.x, terrain.city_level, Site.CENTER.y)
	ground_details.add_child(field)

	# Bucket blades into ~22 m cells so each MultiMesh gets a tight AABB and the
	# engine frustum-culls the chunks the player isn't looking at.
	const CELL := 22.0
	var cells := {}
	for i in places.size():
		var key := Vector2i(floori(places[i].x / CELL), floori(places[i].z / CELL))
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(i)
	for key in cells:
		var idx: PackedInt32Array = cells[key]
		var cmm := MultiMesh.new()
		cmm.transform_format = MultiMesh.TRANSFORM_3D
		cmm.use_custom_data = true
		cmm.mesh = blade
		cmm.instance_count = idx.size()
		# 12 transform floats (identity basis + translation) then 4 custom floats.
		var buf := PackedFloat32Array()
		buf.resize(idx.size() * 16)
		for j in idx.size():
			var o := j * 16
			var p: Vector3 = places[idx[j]]
			var c: Color = customs[idx[j]]
			buf[o] = 1.0
			buf[o + 3] = p.x
			buf[o + 5] = 1.0
			buf[o + 7] = p.y
			buf[o + 10] = 1.0
			buf[o + 11] = p.z
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = c.a
		cmm.buffer = buf
		var chunk := MultiMeshInstance3D.new()
		chunk.multimesh = cmm
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.extra_cull_margin = 1.0  # blades lean a little past the tight bounds
		field.add_child(chunk)

func _path(center: Vector2, size: Vector2, material: Material) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = Vector3(Site.CENTER.x + center.x, terrain.city_level + 0.025, Site.CENTER.y + center.y)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_details.add_child(instance)
