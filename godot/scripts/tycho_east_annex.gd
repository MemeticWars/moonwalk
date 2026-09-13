extends Node3D
## East annex, alongside the central-peak power plant: a second full dome
## (D2, same core building skeleton as D1: central-house, central-building,
## the six-tower block-of-flats arc with its connectors, twin-houses and the
## two L-buildings -- greenhouses/tanks/benches/masts/trees are D1-only,
## kept out of scope here) plus three half-scale mini-domes (m1 east, m2
## south, m3 west of D1 -- m3 moved here from north, its old slot now held
## by the solar array below), joined by simple walkable airlock tunnels.
## Connection graph: m1-D1, m2-D1, m3-D1, m2-D2 -- D2 sits further south,
## beyond m2, and only m2 bridges the two big domes.
##
## Mini/D2 building placement is paused for now (m3, the west mini-dome,
## holds the excavated fish pond) -- every dome here is currently
## an empty shell plus its tunnel. _build_d2_habitat()/_build_mini_habitat()
## are kept below, unused, to restore later.
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
	_build_dome(City.D2_CENTER, d2_level, City.D2_RADIUS, City.D2_HEIGHT,
		City.tunnel_cuts_toward(City.D2_CENTER, [City.M2_CENTER], City.D2_RADIUS))
	_build_dome(City.M1_CENTER, m1_level, City.MINI_RADIUS, City.MINI_HEIGHT,
		City.tunnel_cuts_toward(City.M1_CENTER, [Site.CENTER], City.MINI_RADIUS))
	_build_dome(City.M2_CENTER, m2_level, City.MINI_RADIUS, City.MINI_HEIGHT,
		City.tunnel_cuts_toward(City.M2_CENTER, [Site.CENTER, City.D2_CENTER], City.MINI_RADIUS))
	_build_dome(City.M3_CENTER, m3_level, City.MINI_RADIUS, City.MINI_HEIGHT,
		City.tunnel_cuts_toward(City.M3_CENTER, [Site.CENTER], City.MINI_RADIUS))
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

## Same core skeleton as tycho_city.gd's _layout(): central-house,
## central-building, the six-tower arc with connectors, twin-houses and the
## two L-buildings. Greenhouses/tanks/benches/masts/the tree garden are
## D1-only and stay out of scope here.
func _build_d2_habitat(center: Vector2, level: float) -> void:
	_place(center, level, "central-house", 0, 35)
	_place(center, level, "central-building", 69, -20)
	for side in [-1.0, 1.0]:
		var towers: Array[Vector2] = [Vector2(side * 34, 58), Vector2(side * 56, 38), Vector2(side * 68, 10)]
		for tower: Vector2 in towers:
			_place(center, level, "block-of-flats", tower.x, tower.y)
		for i in 2:
			var mid := (towers[i] + towers[i + 1]) * 0.5
			var direction := towers[i + 1] - towers[i]
			var lift := float(dimensions["block-of-flats"].size_m[1]) * 2.0 / 3.0 - float(dimensions["link-between-block-of-flats"].size_m[1]) * 0.5
			var span := direction.length() - float(dimensions["block-of-flats"].size_m[0]) * 0.8
			_place(center, level, "link-between-block-of-flats", mid.x, mid.y, atan2(-direction.y, direction.x), lift, span)
	for z in [-22.0, 0.0, 22.0]:
		_place(center, level, "twin-houses", -39, z, PI / 2.0)
	_place(center, level, "twin-houses", 43, 0, -PI / 2.0)
	_place(center, level, "l-shape-building", -52, -44)
	_place(center, level, "l-shape-building", 52, -44, 0.0, 0.0, -1.0, true)

## Twin-houses + one L-building, sized to comfortably clear a 50 m dome wall.
func _build_mini_habitat(center: Vector2, level: float) -> void:
	_place(center, level, "twin-houses", -14.0, -14.0, PI / 2.0)
	_place(center, level, "twin-houses", 14.0, -14.0, PI / 2.0)
	_place(center, level, "l-shape-building", 0.0, 16.0)

func _place(base: Vector2, level: float, kind: String, x: float, z: float, yaw: float = 0.0, lift: float = 0.0, span: float = -1.0, mirror: bool = false) -> void:
	var asset := kind + "-mirrored" if mirror else kind
	var scene := load(ASSETS + asset + ".glb") as PackedScene
	var root := scene.instantiate() as Node3D
	root.name = kind
	root.position = Vector3(base.x + x, level + lift, base.y + z)
	root.rotation.y = yaw
	if kind == "block-of-flats":
		root.scale *= 1.2
	var size: Array = dimensions[kind].size_m
	if span > 0.0:
		root.scale.x = span / float(size[0])
	add_child(root)
	var body := StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span if span > 0.0 else float(size[0]), float(size[1]), float(size[2]))
	if kind == "link-between-block-of-flats":
		box.size.y = 2.0
		collider.position.y = float(size[1]) - 2.0
	collider.position.y += box.size.y * 0.5
	collider.shape = box
	body.add_child(collider)

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
