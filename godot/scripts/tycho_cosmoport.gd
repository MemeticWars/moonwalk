extends Node3D
## Hopper landing field just outside the Tycho dome, beside the highway gate.
## Everything is in the city-pad local frame (origin at Site.CENTER, y = 0 at
## city_level); the caller positions the node. Mostly a short-range surface
## delivery port -- one logistics-base building and two hopper pads -- plus
## one InPost cargo lander hovering ten metres above the centre of the main
## octagonal landing apron.

const BASE := "res://assets/colonies/tycho/modules/cosmoport.glb"
const HOPPER := "res://assets/colonies/tycho/modules/delivery-hopper.glb"
const ROCKET := "res://assets/colonies/tycho/modules/rocket_lunar_cargo_transport.glb"
const ROCKET_HEIGHT_M := 22.0
const ROCKET_GROUND_CLEARANCE_M := 10.0
## Landing apron radius, in the same cosmoport-local frame as highway_origin --
## exposed so tycho_city.gd can grade a matching terrain pad for it (see
## _build_paths()'s gate/apron add_city_pad calls) before this node samples
## the ground here.
const APRON_RADIUS := 52.0
const TRUCK_PARKING_WIDTH := 44.0
const TRUCK_PARKING_LENGTH := 42.0
const TRUCK_PARKING_SLOT_WIDTH := 16.0
const TRUCK_PARKING_SLOT_LENGTH := 28.0

var terrain: Node3D
var gate_dir := Vector2(0.0, -1.0)       # unit XZ from the dome centre toward the gate
var highway_dir := Vector2(0.0, -1.0)    # baked highway heading, cosmoport-local XZ
var highway_origin := Vector2(0.0, 0.0)  # highway centreline = origin + highway_dir * station_m
var truck_stands := PackedVector3Array()
var truck_departure := Vector3.FORWARD
var test_mode := false

func truck_parking_center(gate: Vector2, highway: Vector2) -> Vector2:
	var side := Vector2(-highway.normalized().y, highway.normalized().x)
	# Outside the portal, beside its approach road and safely short of the motorway.
	return gate.normalized() * 132.0 + side * 35.0

func truck_stands_global() -> PackedVector3Array:
	var result := PackedVector3Array()
	for stand in truck_stands:
		result.append(to_global(stand))
	return result

func truck_departure_global() -> Vector3:
	return (global_transform.basis * truck_departure).normalized()

func _ready() -> void:
	name = "TychoCosmoport"
	var gate := Vector3(gate_dir.x, 0.0, gate_dir.y).normalized()
	var hwy := Vector3(highway_dir.x, 0.0, highway_dir.y).normalized()
	var hwy_side := Vector3(-hwy.z, 0.0, hwy.x)
	var o := Vector3(highway_origin.x, 0.0, highway_origin.y)

	var metal := _mat(Color("9aa4ad"), 0.55, 0.35)
	var concrete := _mat(Color("6c6f73"), 0.0, 0.95)
	var pad_mat := _mat(Color("3c3f43"), 0.1, 0.85)
	var hazard := _mat(Color("d8b53a"), 0.1, 0.7)

	var apron_top := 0.28
	var parking_c := Vector3(truck_parking_center(gate_dir, highway_dir).x, 0.0, truck_parking_center(gate_dir, highway_dir).y)
	# The pad is registered before its deck and collision are made. This prevents
	# the large trucks from spawning with half their wheels over an ungraded slope.
	terrain.add_city_pad(Vector2(position.x + parking_c.x, position.z + parking_c.z), 38.0, 30.0, 80.0, position.y)

	# --- Forecourt at the dome gate. It is an access road, not motorway pavement.
	_slab(o + hwy * 64.0 + gate * 5.0, gate, 22.0, 32.0, 0.12, concrete, true)

	# --- Landing apron, set well back from the carriageway. The motorway begins
	# at station 150; both local roads meet its rail-free opening at station 175.
	var junction := o + hwy * 175.0
	var apron_c := o + hwy * 150.0 + hwy_side * 95.0
	var apron_r := APRON_RADIUS
	var ground := _min_ground(apron_c, apron_r)
	_octagon(apron_c, apron_r, apron_top, ground - 0.2, concrete)
	_body_box(apron_c + Vector3.UP * (apron_top * 0.5), Vector3(apron_r * 1.9, maxf(0.6, apron_top - ground + 0.4), apron_r * 1.9))

	# --- City access arrives on one side of the motorway opening. It bends clear
	# of the airlock instead of lying beneath the main deck.
	var gate_exit := gate * 105.0
	var access_end := junction - hwy_side * 6.0
	var access_handle := gate_exit.distance_to(access_end) * 0.38
	var access: Array[Vector3] = []
	for k in 21:
		var t := float(k) / 20.0
		access.append(gate_exit.bezier_interpolate(gate_exit + gate * access_handle, access_end - hwy * access_handle, access_end, t))
	_ribbon(access, 11.0, concrete)

	# --- Freight staging outside the airlock. Two 12 m autonomous haulers fit
	#     side by side without occupying the portal or the access-road centreline.
	_slab(parking_c, gate, TRUCK_PARKING_WIDTH, TRUCK_PARKING_LENGTH, 0.16, pad_mat, true)
	truck_departure = gate
	for side_sign in [-1.0, 1.0]:
		var stand: Vector3 = parking_c + hwy_side * side_sign * (TRUCK_PARKING_SLOT_WIDTH * 0.58)
		truck_stands.append(stand + Vector3.UP * 0.24)
		_slot_outline(stand + Vector3.UP * 0.17, gate, TRUCK_PARKING_SLOT_WIDTH, TRUCK_PARKING_SLOT_LENGTH, hazard)
		_lamp(stand + hwy_side * (TRUCK_PARKING_SLOT_WIDTH * 0.5 + 2.0) + Vector3.UP * 0.16)

	# --- Curved off-ramp leaves the opposite side of the same opening and sweeps
	#     out toward the apron. No motorway rail crosses either local road.
	var ramp_in := junction + hwy_side * 6.0
	var ramp_out := apron_c - hwy_side * (apron_r - 8.0)
	var y_hi: float = terrain.height_at(position.x + junction.x, position.z + junction.z) - position.y + 0.4
	var handle := ramp_in.distance_to(ramp_out) * 0.42
	var ramp: Array[Vector3] = []
	var steps := 28
	for k in steps + 1:
		var t := float(k) / steps
		var p: Vector3 = ramp_in.bezier_interpolate(ramp_in + hwy * handle, ramp_out - hwy * handle, ramp_out, t)
		p.y = lerpf(y_hi, apron_top, smoothstep(0.0, 1.0, t))
		ramp.append(p)
	_ribbon(ramp, 11.0, concrete)

	# --- Logistics-base building on the far side of the apron, entrance to the ramp.
	var base := _load_prop(BASE, false)
	var raw := _bounds(base)
	var bscale := 75.0 / maxf(raw.size.x, raw.size.z)
	base.scale = Vector3.ONE * bscale
	var base_c := apron_c + hwy_side * 6.0
	base.position = base_c + Vector3.UP * (apron_top - raw.position.y * bscale)
	base.rotation.y = atan2(hwy_side.x, hwy_side.z)  # face back toward the highway
	_body_box(base_c + Vector3.UP * (apron_top + raw.size.y * bscale * 0.5), Vector3(raw.size.x * bscale, raw.size.y * bscale + 1.0, raw.size.z * bscale), base.rotation.y)

	# --- InPost cargo lander at the centre of the main landing apron. Its legs
	# deliberately remain 10 m above the local ground, leaving the octagon clear
	# for loading equipment and making the elevated landing position unambiguous.
	var rocket := _load_prop(ROCKET, false)
	rocket.name = "CargoRocket"
	var rraw := _bounds(rocket)
	var rscale := ROCKET_HEIGHT_M / maxf(rraw.size.y, 0.000000001)
	rocket.scale = Vector3.ONE * rscale
	# rraw.position.y is the model's lowest point (its landing legs) measured
	# from its own local origin -- negative, so the origin sits above the
	# legs; subtracting it (scaled) raises the origin by that much so the legs
	# land exactly at the requested clearance instead of the model origin.
	var rocket_ground: float = terrain.height_at(position.x + apron_c.x, position.z + apron_c.z) - position.y
	rocket.position = apron_c + Vector3.UP * (rocket_ground + ROCKET_GROUND_CLEARANCE_M - rraw.position.y * rscale)
	rocket.rotation.y = base.rotation.y
	_body_box(rocket.position + Vector3.UP * (rraw.size.y * rscale * 0.5), Vector3(rraw.size.x * rscale + 0.4, rraw.size.y * rscale, rraw.size.z * rscale + 0.4), rocket.rotation.y)

	# --- Two hopper pads on the highway side of the apron, each with a parked hopper.
	for s: float in [-1.0, 1.0]:
		var c: Vector3 = apron_c - hwy_side * 22.0 + hwy * (s * 20.0)
		_pad_ring(c, 7.0, apron_top + 0.06, hazard, pad_mat)
		for k in 6:
			var a := TAU * float(k) / 6.0
			_box(c + Vector3(cos(a), 0.0, sin(a)) * 6.2 + Vector3.UP * (apron_top + 0.35), Vector3(0.5, 0.7, 0.5), metal)
		var hop := _load_prop(HOPPER, false)
		var hb := _bounds(hop)
		var hscale := 5.6 / maxf(hb.size.y, 0.001)
		hop.scale = Vector3.ONE * hscale
		hop.position = c + Vector3.UP * (apron_top - hb.position.y * hscale)
		hop.rotation.y = s * 0.5
		_body_box(hop.position + Vector3.UP * (hb.size.y * hscale * 0.45), Vector3(hb.size.x * hscale + 0.4, hb.size.y * hscale, hb.size.z * hscale + 0.4))

	# --- Lighting: apron perimeter + off-ramp posts.
	for k in 10:
		var a := TAU * float(k) / 10.0
		_lamp(apron_c + Vector3(cos(a), 0.0, sin(a)) * (apron_r - 2.0) + Vector3.UP * apron_top)
	for k in range(3, ramp.size() - 2, 5):
		var t := (ramp[k] - ramp[k - 1]).normalized()
		_lamp(Vector3(ramp[k].x, ramp[k].y, ramp[k].z) + Vector3(-t.z, 0.0, t.x) * 7.0)

	var board := Label3D.new()
	board.text = "TYCHO · COSMOPORT"
	board.font_size = 90
	board.pixel_size = 0.02
	board.modulate = Color("f2c469")
	board.position = junction + hwy_side * 11.0 + Vector3.UP * (y_hi + 4.0)
	board.rotation.y = atan2(-hwy.x, -hwy.z)
	add_child(board)


# ---------------------------------------------------------------- helpers

func _load_prop(path: String, regen_normals: bool) -> Node3D:
	var inst: Node3D
	if test_mode:
		inst = Node3D.new()
		var preview := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(12.0, 6.0, 12.0)
		preview.mesh = box
		inst.add_child(preview)
	else:
		inst = (load(path) as PackedScene).instantiate() as Node3D
	add_child(inst)
	var meshes: Array = inst.find_children("*", "MeshInstance3D", true, false)
	if regen_normals:
		# Fallback for a raw Meshy "_generate" GLB (positions only, no
		# normals/UVs/material) -- rebuild each surface with generated normals
		# and a plain habitat material so it lights correctly. Both live GLBs
		# are fully textured, so this path is currently unused.
		var skin := _mat(Color("b7bcb0"), 0.16, 0.66)
		skin.emission_enabled = true
		skin.emission = Color("30402c")
		skin.emission_energy_multiplier = 0.12
		for m: MeshInstance3D in meshes:
			if m.mesh == null:
				continue
			var rebuilt := ArrayMesh.new()
			for si in m.mesh.get_surface_count():
				var st := SurfaceTool.new()
				st.create_from(m.mesh, si)
				st.generate_normals()
				st.commit(rebuilt)
			for si in rebuilt.get_surface_count():
				rebuilt.surface_set_material(si, skin)
			m.mesh = rebuilt
	for m: MeshInstance3D in meshes:
		m.visibility_range_end = 900.0
		m.lod_bias = 1.6
	return inst

func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m

func _bounds(node: Node) -> AABB:
	var out := AABB()
	var seeded := false
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var box: AABB = m.mesh.get_aabb()
		if not seeded:
			out = box
			seeded = true
		else:
			out = out.merge(box)
	return out

func _min_ground(local_centre: Vector3, radius: float) -> float:
	var lowest := 1e9
	for k in 9:
		var a := TAU * float(k) / 9.0
		var w := Vector3(local_centre.x + cos(a) * radius * 0.7, 0.0, local_centre.z + sin(a) * radius * 0.7)
		lowest = minf(lowest, terrain.height_at(position.x + w.x, position.z + w.z) - position.y)
	return minf(lowest, 0.0)

func _slab(centre: Vector3, dir: Vector3, width: float, length: float, thickness: float, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, thickness, length)
	mesh.material = mat
	mi.mesh = mesh
	mi.position = centre + Vector3.UP * (thickness * 0.5)
	mi.rotation.y = atan2(dir.x, dir.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if collide:
		_body_box(centre + Vector3.UP * (thickness * 0.5), Vector3(width, thickness + 0.3, length), mi.rotation.y)

func _slot_outline(centre: Vector3, dir: Vector3, width: float, length: float, mat: Material) -> void:
	var side := Vector3(-dir.z, 0.0, dir.x).normalized()
	for offset in [-width * 0.5, width * 0.5]:
		var stripe := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.18, 0.025, length)
		mesh.material = mat
		stripe.mesh = mesh
		stripe.position = centre + side * offset
		stripe.rotation.y = atan2(dir.x, dir.z)
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stripe)

func _ribbon(points: Array[Vector3], width: float, mat: Material) -> void:
	# A driveable deck along a polyline: one shallow rotated box per segment, with
	# a matching collider. Segments overlap slightly so the curve reads seamless.
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg := b - a
		var span := Vector2(seg.x, seg.z).length()
		if span < 0.01:
			continue
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, 0.16, span + 0.5)
		mesh.material = mat
		mi.mesh = mesh
		mi.position = (a + b) * 0.5 + Vector3.DOWN * 0.08
		mi.rotation.y = atan2(seg.x, seg.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_body_box(mi.position, Vector3(width, 0.5, span + 0.5), mi.rotation.y)

func _octagon(centre: Vector3, radius: float, top: float, bottom: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var rim: Array[Vector3] = []
	for k in 8:
		var a := PI / 8.0 + TAU * float(k) / 8.0
		rim.append(Vector3(cos(a), 0.0, sin(a)) * radius)
	for k in 8:
		var p0 := rim[k]
		var p1 := rim[(k + 1) % 8]
		_quad(st, p0 + Vector3.UP * top, p1 + Vector3.UP * top, Vector3(0, top, 0), Vector3(0, top, 0))
		_quad(st, p0 + Vector3.UP * top, p0 + Vector3.UP * bottom, p1 + Vector3.UP * bottom, p1 + Vector3.UP * top)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = centre
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _pad_ring(centre: Vector3, radius: float, top: float, ring_mat: Material, disc_mat: Material) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.12
	cyl.material = disc_mat
	disc.mesh = cyl
	disc.position = centre + Vector3.UP * top
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.6
	torus.outer_radius = radius
	torus.rings = 40
	torus.material = ring_mat
	ring.mesh = torus
	ring.position = centre + Vector3.UP * (top + 0.05)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

func _box(centre: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = centre
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p in [a, b, c, a, c, d]:
		st.add_vertex(p)

func _body_box(centre: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = centre
	body.rotation.y = yaw
	add_child(body)

func _lamp(base: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.11
	cyl.height = 6.0
	cyl.material = _mat(Color("8b949c"), 0.5, 0.4)
	pole.mesh = cyl
	pole.position = base + Vector3.UP * 3.0
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pole)
	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.18, 0.5)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ffca7a")
	glow.emission_enabled = true
	glow.emission = Color("ffb64d")
	glow.emission_energy_multiplier = 3.0
	box.material = glow
	head.mesh = box
	head.position = base + Vector3.UP * 6.0
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	var light := OmniLight3D.new()
	light.light_color = Color("ffbb66")
	light.light_energy = 2.4
	light.omni_range = 16.0
	light.position = base + Vector3.UP * 5.7
	add_child(light)
