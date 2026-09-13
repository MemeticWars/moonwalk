extends Node3D
## East annex, alongside the central-peak power plant: a second full dome
## (D2, seven apartment towers, smaller twin/L homes and a birch/pine park)
## plus three half-scale mini-domes (m1 east, m2
## south, m3 west of D1 -- m3 moved here from north, its old slot now held
## by the solar array below), joined by simple walkable airlock tunnels.
## Connection graph: m1-D1, m2-D1, m3-D1, m2-D2 -- D2 sits further south,
## beyond m2, and only m2 bridges the two big domes.
##
## m1 is the greenhouse quarter, m2 is a small residential quarter, and m3
## keeps only three small homes around its excavated fish pond. Every dome has
## lawn and a continuous pedestrian route from its centre through its tunnels.
##
## Deliberately independent of tycho_city.gd's own descriptor/streaming
## system (which is tuned and tested for exactly D1's 65 modules, with
## precise footprint colliders and roof-climbing surfaces): this script uses
## its own simple bounding-box collision for every module here, like
## tycho_power_plant.gd. Site centres/radii and the tunnel-cut helpers live
## on tycho_city.gd (this node's parent), since D1's own dome (built there)
## needs matching cuts toward m1/m2/m3.
const City := preload("res://scripts/tycho_city.gd")
const Site := preload("res://scripts/tycho_site.gd")
const WaterLayout := preload("res://scripts/tycho_water_layout.gd")
const ASSETS := "res://assets/colonies/tycho/modules/"
const GRASS_BLADE := preload("res://shaders/grass_blade.gdshader")
const GRASS_FIELD := preload("res://scripts/tycho_grass.gd")
## Due north (m3's old slot) is no longer free: tycho_city.gd now grades its
## own gate/forecourt/junction and cosmoport-apron pads there (the real
## terrain climbs steeply on that side, toward the summit), and their
## combined reach covers that whole direction. South-east, between m1's and
## m2's own pads, is the nearest clear bearing at the same 170 m radius every
## mini-dome uses -- clear of D1, m1, m2, m3, D2 and both new gate/apron pads
## with 55+ m to spare on every side. The additional local power source asked
## for alongside (not instead of) the one on the real central-peak summit;
## solar panels sample terrain height per-panel already, so this needs no
## flat pad of its own.
const SOLAR_SITE := Site.CENTER + Vector2(120.2, 120.2)
const FLOOR_THICKNESS := 0.3
## Tunnel passage: a square cross-section, double the habitat-tunnel
## module's own natural (near-square, not quite -- 3.43 x 3.09 m) size,
## i.e. 2x the larger of the two: 2 * 3.431572 m. tycho_city.gd's
## TUNNEL_HALF_WIDTH/TUNNEL_CUT_HEIGHT (the dome-wall doorway cut every
## tunnel passes through) were widened to match.
const CROSS_SECTION_SIDE := 2.0 * 3.431572198867798
var terrain: Node3D
var dimensions: Dictionary = {}
var built := false
var habitat_descriptors: Array[Dictionary] = []
var pedestrian_segments: Array[PackedVector2Array] = []

func _ready() -> void:
	name = "TychoEastAnnex"
	dimensions = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "modules.json"))

func _sites() -> Array[Vector2]:
	return [City.D2_CENTER, City.M1_CENTER, City.M2_CENTER, City.M3_CENTER, SOLAR_SITE]

func _process(_delta: float) -> void:
	var near := false
	for site: Vector2 in _sites():
		var tile := Vector2i(floori(site.x / terrain.TILE), floori(site.y / terrain.TILE))
		if maxi(absi(tile.x - terrain.center.x), absi(tile.y - terrain.center.y)) <= terrain.FAR_RADIUS:
			near = true
			break
	if near == built:
		return
	built = near
	if near:
		_build()
	else:
		for child in get_children():
			child.queue_free()

func _build() -> void:
	# Every dome here is levelled flat to D1's own city_level (not each
	# pad's own independently-surveyed local median, which used to differ
	# by several metres pad to pad on the nominally flat crater floor) --
	# one shared plane keeps every tunnel level end to end and keeps the
	# park pond -> stream -> m3 pond water feature at one consistent height.
	var d1_level: float = terrain.city_level
	var d2_level: float = terrain.add_city_pad(City.D2_CENTER, City.D2_RADIUS, 45.0, 80.0, d1_level)
	var m1_level: float = terrain.add_city_pad(City.M1_CENTER, City.MINI_RADIUS, City.MINI_BLEND, 80.0, d1_level)
	var m2_level: float = terrain.add_city_pad(City.M2_CENTER, City.MINI_RADIUS, City.MINI_BLEND, 80.0, d1_level)
	var m3_level: float = terrain.add_city_pad(City.M3_CENTER, City.MINI_RADIUS, City.MINI_BLEND, 80.0, d1_level)
	habitat_descriptors.clear()
	pedestrian_segments.clear()
	_build_dome(City.D2_CENTER, d2_level, City.D2_RADIUS, City.D2_HEIGHT,
		City.tunnel_cuts_toward(City.D2_CENTER, [City.M2_CENTER], City.D2_RADIUS))
	_build_dome(City.M1_CENTER, m1_level, City.MINI_RADIUS, City.MINI_HEIGHT,
		City.tunnel_cuts_toward(City.M1_CENTER, [Site.CENTER], City.MINI_RADIUS))
	_build_dome(City.M2_CENTER, m2_level, City.MINI_RADIUS, City.MINI_HEIGHT,
		City.tunnel_cuts_toward(City.M2_CENTER, [Site.CENTER, City.D2_CENTER], City.MINI_RADIUS))
	_build_dome(City.M3_CENTER, m3_level, City.MINI_RADIUS, City.MINI_HEIGHT,
		City.tunnel_cuts_toward(City.M3_CENTER, [Site.CENTER], City.MINI_RADIUS))
	_build_d2_habitat(City.D2_CENTER, d2_level)
	_build_m1_greenhouse_quarter(City.M1_CENTER, m1_level)
	_build_mini_habitat(City.M2_CENTER, m2_level, "m2")
	_build_mini_habitat(City.M3_CENTER, m3_level, "m3")
	_build_d2_park(City.D2_CENTER, d2_level)
	_build_pedestrian_network(d1_level)
	_build_lawn(City.D2_CENTER, d2_level, City.D2_RADIUS - 7.0, "D2")
	_build_lawn(City.M1_CENTER, m1_level, City.MINI_RADIUS - 4.0, "m1")
	_build_lawn(City.M2_CENTER, m2_level, City.MINI_RADIUS - 4.0, "m2")
	_build_lawn(City.M3_CENTER, m3_level, City.MINI_RADIUS - 4.0, "m3")
	_build_tunnel(Site.CENTER, d1_level, 100.0, City.M1_CENTER, m1_level, City.MINI_RADIUS)
	_build_tunnel(Site.CENTER, d1_level, 100.0, City.M2_CENTER, m2_level, City.MINI_RADIUS)
	_build_tunnel(Site.CENTER, d1_level, 100.0, City.M3_CENTER, m3_level, City.MINI_RADIUS)
	_build_west_walkway(d1_level)
	_build_tunnel(City.M2_CENTER, m2_level, City.MINI_RADIUS, City.D2_CENTER, d2_level, City.D2_RADIUS)
	_build_solar_array()

func _build_dome(center: Vector2, level: float, radius: float, height: float, cuts: Array[Dictionary]) -> void:
	var dome := preload("res://scripts/tycho_dome.gd").new()
	dome.position = Vector3(center.x, level, center.y)
	dome.dome_radius = radius
	dome.dome_height = height
	dome.extra_cuts = cuts
	add_child(dome)

## Seven towers form a loose outer arc, leaving the north-south pedestrian
## spine and the east-side park open. Smaller homes fill the west/south bays.
func _build_d2_habitat(center: Vector2, level: float) -> void:
	var towers: Array[Vector2] = [
		Vector2(-62, 42), Vector2(-70, 8), Vector2(-60, -34),
		Vector2(0, 67),
		Vector2(60, -34), Vector2(70, 8), Vector2(62, 42),
	]
	for tower: Vector2 in towers:
		_place(center, level, "block-of-flats", tower.x, tower.y, 0.0, 0.0, -1.0, false, "D2")
	for z in [-40.0, -16.0, 16.0]:
		_place(center, level, "twin-houses", -31.0, z, PI / 2.0, 0.0, -1.0, false, "D2")
	_place(center, level, "twin-houses", 30.0, -42.0, 0.0, 0.0, -1.0, false, "D2")
	_place(center, level, "l-shape-building", -31.0, 47.0, PI, 0.0, -1.0, false, "D2")
	_place(center, level, "l-shape-building", 31.0, -13.0, PI, 0.0, -1.0, true, "D2")

## Twin-houses + one L-building, sized to comfortably clear a 50 m dome wall.
## This deliberately remains only three homes in lake-dome m3.
func _build_mini_habitat(center: Vector2, level: float, site_name: String) -> void:
	if site_name == "m3":
		# Keep the broad lake and its east-west boardwalk open.
		_place(center, level, "twin-houses", -20.0, 29.0, 0.0, 0.0, -1.0, false, site_name)
		_place(center, level, "twin-houses", 20.0, 29.0, 0.0, 0.0, -1.0, false, site_name)
		_place(center, level, "l-shape-building", 0.0, -31.0, 0.0, 0.0, -1.0, false, site_name)
	else:
		_place(center, level, "twin-houses", -15.0, -15.0, PI / 2.0, 0.0, -1.0, false, site_name)
		_place(center, level, "twin-houses", 15.0, -15.0, PI / 2.0, 0.0, -1.0, false, site_name)
		_place(center, level, "l-shape-building", -22.0, 17.0, 0.0, 0.0, -1.0, false, site_name)

func _build_m1_greenhouse_quarter(center: Vector2, level: float) -> void:
	_place(center, level, "twin-houses", -15.0, -25.0, PI / 2.0, 0.0, -1.0, false, "m1")
	_place(center, level, "l-shape-building", -23.0, 17.0, PI / 2.0, 0.0, -1.0, false, "m1")
	# Three times D1's three-bay row, arranged around a clear west-centre path.
	for x in [7.0, 19.0, 31.0]:
		for z in [-24.0, -12.0, 0.0]:
			_place(center, level, "greenhouse", x, z, 0.0, 0.0, -1.0, false, "m1")

func _place(base: Vector2, level: float, kind: String, x: float, z: float, yaw: float = 0.0, lift: float = 0.0, span: float = -1.0, mirror: bool = false, site_name: String = "") -> void:
	var asset := kind + "-mirrored" if mirror else kind
	var scene := load(ASSETS + asset + ".glb") as PackedScene
	var root := scene.instantiate() as Node3D
	root.name = kind
	root.position = Vector3(base.x + x, level + lift, base.y + z)
	root.rotation.y = yaw
	root.set_meta("kind", kind)
	root.set_meta("site", site_name)
	if kind == "block-of-flats":
		root.scale *= 1.2
	if kind == "greenhouse":
		root.scale.x *= 0.5
	var size: Array = dimensions[kind].size_m
	if span > 0.0:
		root.scale.x = span / float(size[0])
	add_child(root)
	habitat_descriptors.append({"kind": kind, "site": site_name, "point": base + Vector2(x, z), "yaw": yaw})
	var body := StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span if span > 0.0 else float(size[0]), float(size[1]), float(size[2]))
	if kind == "greenhouse":
		# The scene root is halved on X; compensate here so its prepared 12 m
		# footprint, rather than a second accidental halving, remains collidable.
		box.size.x *= 2.0
	elif kind.begins_with("park-"):
		box.size = Vector3(0.35, minf(4.0, float(size[1])), 0.35)
	if kind == "link-between-block-of-flats":
		box.size.y = 2.0
		collider.position.y = float(size[1]) - 2.0
	collider.position.y += box.size.y * 0.5
	collider.shape = box
	body.add_child(collider)

func _build_d2_park(center: Vector2, level: float) -> void:
	var index := 0
	for x in [18.0, 26.0, 34.0, 42.0]:
		for z in [12.0, 22.0, 32.0, 42.0]:
			var kind := "park-birch" if index % 2 == 0 else "park-pine"
			_place(center, level, kind, x, z, float(index) * 1.71, 0.0, -1.0, false, "D2")
			index += 1

func _build_pedestrian_network(level: float) -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("8d8f8d")
	concrete.roughness = 0.94
	# Each new sphere gets a route from its centre to every connected doorway.
	# The tunnel spans are included, yielding one continuous visible pavement.
	_add_walkway(City.M1_CENTER, Site.CENTER + Vector2(100.0, 0.0), level, concrete, "m1_to_D1")
	_add_walkway(City.M2_CENTER, Site.CENTER + Vector2(0.0, 100.0), level, concrete, "m2_to_D1")
	_add_walkway(City.M2_CENTER, City.D2_CENTER - Vector2(0.0, City.D2_RADIUS), level, concrete, "m2_to_D2")
	_add_walkway(City.D2_CENTER, City.M2_CENTER + Vector2(0.0, City.MINI_RADIUS), level, concrete, "D2_to_m2")
	# The west tunnel reserves its +Z wall for the brook. Its 0.8 m-offset
	# pavement is extended through the m3 lake as a boardwalk to the centre.
	var west_d1 := Site.CENTER + Vector2(-94.0, 0.8)
	var west_m3 := Site.CENTER + Vector2(-135.0, 0.8)
	_add_walkway(City.M3_CENTER, west_m3, level, concrete, "m3_lake_boardwalk")
	pedestrian_segments.append(PackedVector2Array([west_m3, west_d1]))

func _add_walkway(a: Vector2, b: Vector2, level: float, material: Material, path_name: String) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var body := StaticBody3D.new()
	body.name = "PedestrianPath_" + path_name
	body.position = Vector3((a.x + b.x) * 0.5, level + 0.055, (a.y + b.y) * 0.5)
	body.basis = Basis.looking_at(Vector3(b.x - a.x, 0.0, b.y - a.y).normalized(), Vector3.UP)
	var size := Vector3(2.4, 0.10, length)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var surface := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	surface.mesh = mesh
	surface.material_override = material
	body.add_child(surface)
	add_child(body)
	pedestrian_segments.append(PackedVector2Array([a, b]))

func _build_lawn(center: Vector2, level: float, radius: float, site_name: String) -> void:
	var lawn := MeshInstance3D.new()
	lawn.name = "Lawn_" + site_name
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color("35502c")
	green.roughness = 1.0
	surface.set_material(green)
	const CELL := 2.0
	var cells := ceili(radius * 2.0 / CELL)
	for ix in cells:
		for iz in cells:
			var x0 := -radius + float(ix) * CELL
			var z0 := -radius + float(iz) * CELL
			var corners := [Vector2(x0, z0), Vector2(x0 + CELL, z0), Vector2(x0 + CELL, z0 + CELL), Vector2(x0, z0 + CELL)]
			if corners[0].length() > radius and corners[1].length() > radius and corners[2].length() > radius and corners[3].length() > radius:
				continue
			var vertices: Array[Vector3] = []
			for corner: Vector2 in corners:
				var clipped := corner.limit_length(radius)
				var world := center + clipped
				vertices.append(Vector3(clipped.x, terrain.height_at(world.x, world.y) - level + 0.015, clipped.y))
			for order in [[0, 2, 1], [0, 3, 2]]:
				for vertex_index: int in order:
					surface.add_vertex(vertices[vertex_index])
	surface.generate_normals()
	lawn.mesh = surface.commit()
	lawn.position = Vector3(center.x, level, center.y)
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lawn)
	_build_grass(center, level, radius, site_name)

func _build_grass(center: Vector2, level: float, radius: float, site_name: String) -> void:
	var blade := QuadMesh.new()
	blade.size = Vector2(0.02, 0.4)
	blade.center_offset = Vector3(0.0, 0.2, 0.0)
	var grass_material := ShaderMaterial.new()
	grass_material.shader = GRASS_BLADE
	grass_material.set_shader_parameter("emission_amount", 0.5)
	blade.material = grass_material
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(site_name) + 22041
	const SPACING := 0.38
	var steps := floori(radius * 2.0 / SPACING)
	var places: Array[Vector3] = []
	var customs: Array[Color] = []
	for ix in steps:
		for iz in steps:
			var local := Vector2(
				-radius + (float(ix) + 0.5 + rng.randf_range(-0.42, 0.42)) * SPACING,
				-radius + (float(iz) + 0.5 + rng.randf_range(-0.42, 0.42)) * SPACING)
			if local.length() > radius:
				continue
			var world := center + local
			if WaterLayout.depth(world) > 0.02 or _grass_blocked(world, site_name):
				continue
			places.append(Vector3(local.x, terrain.height_at(world.x, world.y) - level + 0.02, local.y))
			customs.append(Color(rng.randf() * TAU, rng.randf() * TAU, clampf(rng.randfn(0.40, 0.10), 0.16, 0.72), rng.randf()))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = blade
	multimesh.instance_count = places.size()
	var buffer := PackedFloat32Array()
	buffer.resize(places.size() * 16)
	for i in places.size():
		var offset := i * 16
		var point := places[i]
		var custom := customs[i]
		buffer[offset] = 1.0
		buffer[offset + 3] = point.x
		buffer[offset + 5] = 1.0
		buffer[offset + 7] = point.y
		buffer[offset + 10] = 1.0
		buffer[offset + 11] = point.z
		buffer[offset + 12] = custom.r
		buffer[offset + 13] = custom.g
		buffer[offset + 14] = custom.b
		buffer[offset + 15] = custom.a
	multimesh.buffer = buffer
	var field := GRASS_FIELD.new()
	field.name = "Grass_" + site_name
	field.terrain = terrain
	field.material = grass_material
	field.position = Vector3(center.x, level, center.y)
	var instances := MultiMeshInstance3D.new()
	instances.multimesh = multimesh
	instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.add_child(instances)
	add_child(field)

func _grass_blocked(point: Vector2, site_name: String) -> bool:
	for segment: PackedVector2Array in pedestrian_segments:
		if _distance_to_segment(point, segment[0], segment[1]) < 1.7:
			return true
	for descriptor: Dictionary in habitat_descriptors:
		if descriptor.site != site_name:
			continue
		var kind: String = descriptor.kind
		var size: Array = dimensions[kind].size_m
		var half := Vector2(float(size[0]), float(size[2])) * 0.5 + Vector2.ONE * 0.7
		if kind == "block-of-flats":
			half *= 1.2
		elif kind.begins_with("park-"):
			half = Vector2.ONE * 2.4
		var local: Vector2 = (point - Vector2(descriptor.point)).rotated(-float(descriptor.yaw))
		if absf(local.x) <= half.x and absf(local.y) <= half.y:
			return true
	return false

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	if delta.length_squared() < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(delta) / delta.length_squared(), 0.0, 1.0)
	return point.distance_to(a + delta * t)

## A habitat-tunnel.glb module (prepared by
## tools/prepare_tycho_habitat_tunnel.py from the Meshy "Lunar Habitat
## Module" GLB, normalized so its long axis is exactly TUNNEL_GAP -- every
## connected dome pair here is sited at that same centre-to-centre gap) plus
## a walkable floor collider. No side-wall collision: at this short, straight
## span the dome-floor/tunnel-floor colliders already keep the player on the
## path, and it avoids trapping them on any small mismatch between the two
## ends' independently graded levels.
func _build_tunnel(a_center: Vector2, a_level: float, a_radius: float, b_center: Vector2, b_level: float, b_radius: float) -> void:
	var direction := (b_center - a_center).normalized()
	var a_point := a_center + direction * a_radius
	var b_point := b_center - direction * b_radius
	var length := a_point.distance_to(b_point)
	if length <= 0.1:
		return
	var mid_xz := (a_point + b_point) * 0.5
	# 1.5 m lower than the two ends' shared floor level, on request (0.5 m more
	# than the original 1 m drop) -- the passage sits well recessed below the
	# surrounding grade instead of flush with it (both ends are already the
	# same level, see _build()'s level_override note, so no per-side slope to
	# average away here).
	var mid_y := (a_level + b_level) * 0.5 - 1.5
	var node := Node3D.new()
	node.name = "AirlockTunnel"
	add_child(node)
	node.position = Vector3(mid_xz.x, mid_y, mid_xz.y)
	node.look_at(Vector3(b_point.x, mid_y, b_point.y), Vector3.UP)
	var module_size: Array = dimensions["habitat-tunnel"].size_m
	var scene := load(ASSETS + "habitat-tunnel.glb") as PackedScene
	var model := scene.instantiate() as Node3D
	model.name = "HabitatTunnelModel"
	# The model's long axis is local X (as exported); rotate 90 degrees so it
	# runs along this node's Z axis, the direction toward b_point.
	model.rotation.y = PI / 2.0
	# Non-uniform scale: X still spans exactly the tunnel gap; Y (height) and
	# Z (width) are scaled independently to CROSS_SECTION_SIDE each, a square
	# passage double the module's own (near-square, but not exact) natural
	# cross-section -- scale.y/scale.z apply in the model's own local axes,
	# unaffected by the rotation.y above (rotation and scale are independent
	# transform components).
	model.scale = Vector3(length / float(module_size[0]),
		CROSS_SECTION_SIDE / float(module_size[1]), CROSS_SECTION_SIDE / float(module_size[2]))
	node.add_child(model)
	var body := StaticBody3D.new()
	body.name = "Floor"
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CROSS_SECTION_SIDE, FLOOR_THICKNESS, length)
	collider.shape = box
	body.add_child(collider)
	node.add_child(body)
	var light := OmniLight3D.new()
	light.light_energy = 1.2
	light.omni_range = length * 0.8
	light.position.y = CROSS_SECTION_SIDE * 0.5
	node.add_child(light)

func _build_west_walkway(level: float) -> void:
	# Inside the west tunnel the brook follows the +Z wall (z=2.5 m).
	# This dry street sits beside it and extends onto both dome approaches.
	var street := StaticBody3D.new()
	street.name = "WestTunnelWalkway"
	street.position = Vector3(WaterLayout.WALKWAY_CENTER.x, level-0.035, WaterLayout.WALKWAY_CENTER.y)
	var size := Vector3(WaterLayout.WALKWAY_SIZE.x,0.12,WaterLayout.WALKWAY_SIZE.y)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	street.add_child(collision)
	var deck := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	deck.mesh = mesh
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("96958d")
	concrete.roughness = 0.92
	deck.material_override = concrete
	street.add_child(deck)
	# A painted edge identifies the brook side without blocking passage.
	var line := MeshInstance3D.new()
	var stripe := BoxMesh.new()
	stripe.size = Vector3(size.x,0.004,0.06)
	line.mesh = stripe
	line.position = Vector3(0,0.062,size.z*0.5-0.10)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("e6d9a4")
	line.material_override = paint
	street.add_child(line)
	add_child(street)

func _build_solar_array() -> void:
	var panel_size: Array = dimensions["fotovoltaic-panels"].size_m
	var panel_box := Vector3(float(panel_size[0]), float(panel_size[1]), float(panel_size[2]))
	for row_z in [0.0, -12.0]:
		for x in [-52.0, -26.0, 0.0, 26.0, 52.0]:
			_place_panel(SOLAR_SITE + Vector2(x, row_z), panel_box)

func _place_panel(point: Vector2, box_size: Vector3) -> void:
	var scene := load(ASSETS + "fotovoltaic-panels.glb") as PackedScene
	var root := scene.instantiate() as Node3D
	root.name = "fotovoltaic-panels"
	root.position = Vector3(point.x, terrain.height_at(point.x, point.y), point.y)
	add_child(root)
	var body := StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	collider.shape = box
	collider.position.y = box_size.y * 0.5
	body.add_child(collider)
