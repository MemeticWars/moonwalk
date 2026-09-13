extends SceneTree

const Layout := preload("res://scripts/tycho_water_layout.gd")
const City := preload("res://scripts/tycho_city.gd")

class FlatTerrain extends "res://scripts/lunar_terrain.gd":
	func _ready() -> void:
		city_enabled = true
		city_level = 10.0
	func _process(_delta: float) -> void:
		pass
	func natural_height(_x: float, _z: float) -> float:
		return 10.0
	func elevation(_latitude: float, _longitude: float) -> float:
		return 10.0
	func latlon_at(_x: float, _z: float) -> Vector2:
		return Vector2.ZERO
	func survey_weight(_x: float, _z: float) -> float:
		return 1.0
	func _build_rocks(_root: Node3D, _key: Vector2i) -> void:
		pass

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := FlatTerrain.new()
	root.add_child(terrain)
	var straight := Layout.Site.CENTER + Vector2(-50,-11)
	var probes := [Layout.POND1_CENTER, Layout.POND2_CENTER, straight, straight + Vector2(0,0.26)]
	var depths := [1.0, 1.5, 0.5, 0.0]
	for x in [-100.5,-110.0,-119.5]:
		probes.append(Layout.Site.CENTER+Vector2(x,Layout.TUNNEL_STREAM_Z))
		depths.append(0.5)
	var built := {}
	for i in probes.size():
		var p: Vector2 = probes[i]
		check(absf(Layout.depth(p)-depths[i]) < 0.0001, "Requested bed depth %d" % i)
		check(absf(terrain.height_at(p.x,p.y)-(10.0-depths[i])) < 0.03, "Sampled bed depth %d" % i)
		var key := Vector2i(floori(p.x/64),floori(p.y/64))
		if not built.has(key):
			var tile := terrain._build_ground(key,0)
			root.add_child(tile)
			built[key] = tile
	check(Layout.depth(straight+Vector2(0,0.125)) > 0.4, "U bed must have rounded bottom, not a V")
	var city := City.new()
	city.dimensions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/colonies/tycho/modules/modules.json"))
	city._layout()
	var route := Layout.route()
	check(route[0] == Layout.POND1_CENTER, "Connected D1 source")
	check(((route[-1]-Layout.POND2_CENTER)/Layout.POND2_RADII).length() < 1.0, "Connected m3 outlet")
	for d: Dictionary in city.descriptors:
		if String(d.kind).begins_with("park-") or d.kind == "link-between-block-of-flats":
			continue
		var size: Array = city.dimensions[d.kind].size_m
		var half := Vector2(size[0],size[2])*0.5
		if d.kind == "block-of-flats":
			half *= 1.2
		for p: Vector2 in route:
			var local := (p-Vector2(d.point)).rotated(-float(d.yaw))
			check(not (absf(local.x)<half.x+0.75 and absf(local.y)<half.y+0.75), "Brook intersects " + str(d.kind))
	for i in range(1,route.size()-1):
		check(absf((route[i]-route[i-1]).angle_to(route[i+1]-route[i])) < 0.25, "Rounded bends without sharp corners")
	# The lawn must descend with the bed; no flat overlay across either bank.
	city.terrain = terrain
	city.ground_details = Node3D.new()
	root.add_child(city.ground_details)
	city._add_city_lawn()
	var lawn: MeshInstance3D = city.ground_details.get_node("CityLawn")
	var lawn_vertices: PackedVector3Array = lawn.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var deepest := 0.0
	for v in lawn_vertices:
		deepest = minf(deepest,v.y)
	check(deepest < -0.98, "Lawn follows the one-metre basin")
	check(city.ground_details.has_node("BrookFootbridge"), "Service lane keeps a walkable bridge")
	city.ground_details.free()
	city.free()
	await physics_frame
	await physics_frame
	for i in probes.size():
		var p: Vector2 = probes[i]
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x,12,p.y),Vector3(p.x,7,p.y))
		var hit := terrain.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "Bed collider present")
		if not hit.is_empty():
			check(absf(hit.position.y-terrain.height_at(p.x,p.y)) < 0.003, "Rendered mesh/collision/height query agree")
	var annex := preload("res://scripts/tycho_east_annex.gd").new()
	annex.terrain = terrain
	root.add_child(annex)
	annex.set_process(false)
	annex._build_west_walkway(10.0)
	check(Layout.TUNNEL_STREAM_Z+Layout.STREAM_WIDTH*0.5 < annex.CROSS_SECTION_SIDE*0.5, "Brook stays inside tunnel wall")
	var street_max_z := Layout.WALKWAY_CENTER.y-Layout.Site.CENTER.y+Layout.WALKWAY_SIZE.y*0.5
	check(street_max_z < Layout.TUNNEL_STREAM_Z-Layout.STREAM_WIDTH*0.5, "Dry street beside brook without overlap")
	await physics_frame
	await physics_frame
	for x in [-94.5,-100.5,-110.0,-119.5,-134.5]:
		var p := Layout.Site.CENTER+Vector2(x,0.8)
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x,12,p.y),Vector3(p.x,7,p.y))
		var hit := terrain.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.get("collider") == annex.get_node("WestTunnelWalkway"), "Walkable street and approaches through tunnel")
	annex.free()
	var water := preload("res://scripts/tycho_water_feature.gd").new()
	water.terrain = terrain
	root.add_child(water)
	water.set_process(false)
	var material := ShaderMaterial.new()
	water._add_pond(Layout.POND1_CENTER,Layout.POND1_RADII,material)
	water._add_stream(material)
	for node: MeshInstance3D in water.get_children():
		var normals: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		check(normals[0].y > 0.9, "Water faces upward: " + str(node.name))
		check(absf(node.position.y-9.875)<0.001, "Ponds and brook must share the water level lowered by 10 cm")
	water.free()
	# Verify all fine/coarse cell transitions along the curved route.
	for p: Vector2 in route:
		var x := floorf(p.x/2)*2
		var z := floorf(p.y/2)*2
		for q in [Vector2(x,p.y), Vector2(p.x,z)]:
			for offset in [Vector2(0.001,0),Vector2(0,0.001)]:
				var a: Vector2 = q-offset
				var b: Vector2 = q+offset
				check(absf(terrain.height_at(a.x,a.y)-terrain.height_at(b.x,b.y)) < 0.08, "Stitched bed has no jump across cell edges")
	for tile: Node in built.values():
		tile.free()
	terrain.free()
	if "--real-dem" in OS.get_cmdline_user_args():
		print("Checking actual Tycho DEM and streamed tiles...")
		var real_terrain := preload("res://scripts/lunar_terrain.gd").new()
		real_terrain.colony = {"name":"Tycho Station", "latitude":-43.66, "longitude":-11.3}
		root.add_child(real_terrain)
		real_terrain.set_process(false)
		real_terrain.add_city_pad(Layout.POND2_CENTER,50.0,22.5,80.0,real_terrain.city_level)
		await process_frame
		for p: Vector2 in route:
			check(absf(real_terrain.raw_height(p.x,p.y) - (real_terrain.city_level-Layout.depth(p))) < 0.03, "Real terrain ridge must not obstruct the brook")
		real_terrain.free()
	print("TYCHO WATER: %d failures; depths, U section, building clearance, rounded route, bed collision, water mesh" % failures)
	quit(1 if failures else 0)
