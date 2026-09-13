extends Node3D
## Triangulated ellipsoidal dome: physical glass prisms, shared frame instances.
const Lorry := preload("res://scripts/lunar_lorry.gd")
const RADIUS := 100.0
const HEIGHT := 90.0
const THICKNESS := 0.24
const SECTORS := 48
const BANDS := 10
const GATE_HEIGHT := 7.5
## The portal GLB (see _add_gate_portal) is scaled to ~GATE_HEIGHT*1.6 tall (~12 m)
## so it reads as a real structure, not a slot exactly GATE_HEIGHT high. The shell
## must stay cut at least that tall or its intact glass/beams/collision above
## GATE_HEIGHT poke straight through the portal's upper half. Keep >= the
## portal's actual scaled height (recompute if the model or its scale changes).
const GATE_CUT_HEIGHT := 13.5
var panel_count := 0
var edge_count := 0
## Ground-level opening in the shell, facing the highway. gate_arc = 0 -> no gate.
## Set by the caller before the node enters the tree.
var gate_angle := 0.0
var gate_arc := 0.0
## Scaled instances (the east annex's mini-domes) set these before entering
## the tree; RADIUS/HEIGHT stay the D1 defaults so roof_height() below (used
## by tycho_weather.gd for the main dome's own rain ceiling) is unaffected.
var dome_radius := RADIUS
var dome_height := HEIGHT
## Plain doorway-sized holes for inter-dome airlock tunnels: no bulkhead, no
## portal model (unlike the single highway gate_angle/gate_arc above) --
## the connecting tunnel mesh built by tycho_east_annex.gd plugs the gap.
## Each entry: {angle: float, arc: float, cut_height: float}.
var extra_cuts: Array[Dictionary] = []

func _in_gate(p: Vector3) -> bool:
	if gate_arc <= 0.0 or p.y > GATE_CUT_HEIGHT:
		return false
	return absf(wrapf(atan2(p.z, p.x) - gate_angle, -PI, PI)) < gate_arc

func _in_extra_cut(p: Vector3) -> bool:
	for cut: Dictionary in extra_cuts:
		if p.y <= cut.cut_height and absf(wrapf(atan2(p.z, p.x) - cut.angle, -PI, PI)) < cut.arc:
			return true
	return false

static func roof_height(radius: float) -> float:
	return HEIGHT * sqrt(maxf(0.0, 1.0 - pow(radius / RADIUS, 2.0)))

func _ready() -> void:
	name = "TychoDome"
	var points: Array[Vector3] = []
	for ring in BANDS:
		var elevation := float(ring) / BANDS * PI * 0.5
		for sector in SECTORS:
			var angle := TAU * float(sector) / SECTORS
			points.append(Vector3(dome_radius * cos(elevation) * cos(angle), dome_height * sin(elevation), dome_radius * cos(elevation) * sin(angle)))
	points.append(Vector3(0, dome_height, 0))
	var faces: Array[Vector3i] = []
	for ring in BANDS - 1:
		for sector in SECTORS:
			var a := ring * SECTORS + sector
			var b := ring * SECTORS + (sector + 1) % SECTORS
			var c := a + SECTORS
			var d := b + SECTORS
			# Alternate diagonals to avoid a spiral stripe across the dome.
			if (ring + sector) % 2 == 0:
				faces.append(Vector3i(a, b, c))
				faces.append(Vector3i(b, d, c))
			else:
				faces.append(Vector3i(a, b, d))
				faces.append(Vector3i(a, d, c))
	for sector in SECTORS:
		faces.append(Vector3i((BANDS - 1) * SECTORS + sector, (BANDS - 1) * SECTORS + (sector + 1) % SECTORS, points.size() - 1))
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := SurfaceTool.new()
	edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	var beams: Dictionary = {}
	var collision_faces := PackedVector3Array()
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color("9babb4")
	frame_material.metallic = 0.65
	frame_material.roughness = 0.32
	var open_faces := 0
	var hole_box := AABB()
	var hole_seeded := false
	for face: Vector3i in faces:
		var a := points[face.x]
		var b := points[face.y]
		var c := points[face.z]
		var center := (a + b + c) / 3.0
		# Leave a ground-level doorway toward the highway: no glass, no collision.
		# Cut on the face centre, not all three vertices -- a triangle straddling
		# the gate boundary (two vertices in, one just outside) would otherwise
		# keep its full glass/collision/beam, leaving a stray frame beam standing
		# as a vertical pole right on the airlock's central axis.
		if _in_gate(center):
			open_faces += 1
			for p in [a, b, c]:
				if not hole_seeded:
					hole_box = AABB(p, Vector3.ZERO)
					hole_seeded = true
				else:
					hole_box = hole_box.expand(p)
			continue
		if _in_extra_cut(center):
			open_faces += 1
			continue
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot(center) < 0:
			normal = -normal
		collision_faces.append_array(PackedVector3Array([a, b, c]))
		# Inset each independent pane from the structural beams; real 24 cm edges.
		a = center.lerp(a, 0.982)
		b = center.lerp(b, 0.982)
		c = center.lerp(c, 0.982)
		var offset := normal * THICKNESS * 0.5
		_triangle(glass, a + offset, b + offset, c + offset, normal)
		_triangle(glass, a - offset, c - offset, b - offset, -normal)
		for pair in [[a, b], [b, c], [c, a]]:
			var u: Vector3 = pair[0]
			var v: Vector3 = pair[1]
			var side_normal := (v - u).cross(normal).normalized()
			if side_normal.dot((u + v) * 0.5 - center) < 0:
				side_normal = -side_normal
			_triangle(edges, u - offset, v - offset, v + offset, side_normal)
			_triangle(edges, u - offset, v + offset, u + offset, side_normal)
		for pair in [[face.x, face.y], [face.y, face.z], [face.z, face.x]]:
			beams[Vector2i(mini(pair[0], pair[1]), maxi(pair[0], pair[1]))] = true
	panel_count = faces.size()
	edge_count = beams.size()
	if gate_arc > 0.0 and hole_seeded:
		collision_faces.append_array(_add_gate_bulkhead(glass, edges, hole_box, frame_material))
	var glass_material := ShaderMaterial.new()
	glass_material.shader = preload("res://shaders/tycho_glass.gdshader")
	var glass_mesh := glass.commit()
	glass_mesh.surface_set_material(0, glass_material)
	_add_mesh(glass_mesh, "GlassPanels", false)
	var edge_material := StandardMaterial3D.new()
	edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_material.albedo_color = Color(0.22, 0.52, 0.57, 0.38)
	edge_material.roughness = 0.18
	var edge_mesh := edges.commit()
	edge_mesh.surface_set_material(0, edge_material)
	_add_mesh(edge_mesh, "GlassThickness", false)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.11
	beam_mesh.bottom_radius = 0.11
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 6
	beam_mesh.rings = 1
	beam_mesh.material = frame_material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = beam_mesh
	multi.instance_count = beams.size()
	var index := 0
	for edge: Vector2i in beams:
		var start := points[edge.x]
		var end := points[edge.y]
		var y := (end - start).normalized()
		var helper := Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
		var x := helper.cross(y).normalized()
		var z := x.cross(y).normalized()
		multi.set_instance_transform(index, Transform3D(Basis(x, y * start.distance_to(end), z), (start + end) * 0.5))
		index += 1
	var frame := MultiMeshInstance3D.new()
	frame.name = "TriangularFrame"
	frame.multimesh = multi
	add_child(frame)
	var rim := TorusMesh.new()
	rim.inner_radius = dome_radius - 0.35
	rim.outer_radius = dome_radius + 0.35
	rim.rings = 192
	rim.ring_segments = 8
	rim.material = frame_material
	_add_mesh(rim, "FoundationRing", true)
	var body := StaticBody3D.new()
	body.name = "DomeCollision"
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(collision_faces)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	if gate_arc > 0.0:
		_add_gate_portal()

const GATE_MODEL := "res://assets/colonies/tycho/modules/colony-gateway.glb"

func _add_gate_portal() -> void:
	# A built airlock/gateway model set into the shell opening, scaled to the cut
	# and pushed mostly outboard of the shell radius, with a 0.5 m extra step
	# inward (past the old flush-with-the-shell placement) so its threshold
	# reads as part of the station interior rather than sitting on the rim.
	var portal := (load(GATE_MODEL) as PackedScene).instantiate() as Node3D
	add_child(portal)
	var box := AABB()
	var seeded := false
	for m: MeshInstance3D in portal.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		box = m.mesh.get_aabb() if not seeded else box.merge(m.mesh.get_aabb())
		seeded = true
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not seeded:
		return
	var opening_width := 2.0 * dome_radius * sin(gate_arc)
	# The model's local +X (not +Z) is its passage axis -- align it with the
	# outward radial, so +Z (the wide face) spans the opening instead.
	var scale := minf(opening_width * 1.02 / maxf(box.size.z, 0.01), GATE_HEIGHT * 1.6 / maxf(box.size.y, 0.01))
	portal.scale = Vector3.ONE * scale
	var radial := Vector3(cos(gate_angle), 0.0, sin(gate_angle))
	portal.rotation.y = atan2(radial.x, radial.z) + PI * 0.5
	var depth := box.size.x * scale
	portal.position = radial * (dome_radius - 2.0 + depth * 0.5) - Vector3(0.0, box.position.y * scale, 0.0)
	# Collide with the gate's own surface, not a box around it -- but the model
	# is a single solid mesh, not a true hollow archway, so its raw trimesh
	# blocks straight-through traffic. Carve a clear driving lane out of the
	# collision along the local +X passage axis: drop every triangle that has
	# a vertex inside the lane's width/height envelope, keeping collision only
	# for the side pillars and the structure above the lane (still real walls,
	# just not ones sitting in the roadway).
	var lane_half_width_local := (Lorry.highway_vehicle_width() + 1.0) / scale
	var lane_ceiling := box.position.y + 6.0 / scale
	var collision_body := StaticBody3D.new()
	collision_body.name = "GatePortalCollision"
	for m: MeshInstance3D in portal.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var faces := m.mesh.get_faces()
		var kept := PackedVector3Array()
		var i := 0
		while i < faces.size():
			var tri := PackedVector3Array([faces[i], faces[i + 1], faces[i + 2]])
			# Test the triangle's bounding interval, not just its vertices --
			# a wide triangle (e.g. a floor slab spanning the whole width) can
			# have both vertices outside the lane while its middle still
			# crosses it, so a per-vertex check would miss it.
			var min_y := minf(tri[0].y, minf(tri[1].y, tri[2].y))
			var min_z := minf(tri[0].z, minf(tri[1].z, tri[2].z))
			var max_z := maxf(tri[0].z, maxf(tri[1].z, tri[2].z))
			var in_lane := min_y < lane_ceiling and max_z >= -lane_half_width_local and min_z <= lane_half_width_local
			if not in_lane:
				kept.append_array(tri)
			i += 3
		if kept.is_empty():
			continue
		var trimesh := ConcavePolygonShape3D.new()
		trimesh.set_faces(kept)
		trimesh.backface_collision = true
		var col := CollisionShape3D.new()
		col.shape = trimesh
		col.transform = m.transform
		collision_body.add_child(col)
	portal.add_child(collision_body)

## The shell cut lands on whole triangulation sectors and bands (see the loop
## in _ready), so the removed hole is wider and taller than opening_width/
## GATE_HEIGHT, the flat dimensions the portal GLB above is actually scaled
## to -- pushing that portal outboard exposed the mismatch as bare gaps beside
## and above it. Close them with a flat glazed bulkhead spanning hole_box (the
## true measured opening), punched with the same passage rectangle the
## portal's own collision is carved to above, so the two openings line up.
func _add_gate_bulkhead(glass: SurfaceTool, edges: SurfaceTool, hole_box: AABB, frame_material: StandardMaterial3D) -> PackedVector3Array:
	var radial := Vector3(cos(gate_angle), 0.0, sin(gate_angle))
	var tangential := Vector3(-radial.z, 0.0, radial.x)
	var half_width := 0.0
	var depth := 0.0
	var corners := [Vector2(hole_box.position.x, hole_box.position.z), Vector2(hole_box.position.x, hole_box.end.z),
		Vector2(hole_box.end.x, hole_box.position.z), Vector2(hole_box.end.x, hole_box.end.z)]
	for corner: Vector2 in corners:
		var p := Vector3(corner.x, 0.0, corner.y)
		half_width = maxf(half_width, absf(p.dot(tangential)))
		depth += p.dot(radial)
	depth /= corners.size()
	var wall_height := hole_box.size.y
	var aperture_half_width := (Lorry.highway_vehicle_width() + 1.0) * 0.5
	var aperture_height := 6.0
	var collision_faces := PackedVector3Array()
	var panels: Array[Vector4] = [Vector4(-half_width, -aperture_half_width, 0.0, wall_height),
		Vector4(aperture_half_width, half_width, 0.0, wall_height)]
	if aperture_height < wall_height:
		panels.append(Vector4(-aperture_half_width, aperture_half_width, aperture_height, wall_height))
	for panel: Vector4 in panels:
		var a := radial * depth + tangential * panel.x + Vector3.UP * panel.z
		var b := radial * depth + tangential * panel.y + Vector3.UP * panel.z
		var c := radial * depth + tangential * panel.y + Vector3.UP * panel.w
		var d := radial * depth + tangential * panel.x + Vector3.UP * panel.w
		collision_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))
		var offset := radial * THICKNESS * 0.5
		_triangle(glass, a + offset, b + offset, c + offset, radial)
		_triangle(glass, a - offset, c - offset, b - offset, -radial)
		_triangle(glass, a + offset, c + offset, d + offset, radial)
		_triangle(glass, a - offset, d - offset, c - offset, -radial)
		var mid := radial * depth + tangential * (panel.x + panel.y) * 0.5 + Vector3.UP * (panel.z + panel.w) * 0.5
		for pair in [[a, b], [b, c], [c, d], [d, a]]:
			var u: Vector3 = pair[0]
			var v: Vector3 = pair[1]
			var side_normal := (v - u).cross(radial).normalized()
			if side_normal.dot((u + v) * 0.5 - mid) < 0:
				side_normal = -side_normal
			_triangle(edges, u - offset, v - offset, v + offset, side_normal)
			_triangle(edges, u - offset, v + offset, u + offset, side_normal)
	var outer_top_l := radial * depth + tangential * -half_width + Vector3.UP * wall_height
	var outer_top_r := radial * depth + tangential * half_width + Vector3.UP * wall_height
	_frame_beam(radial * depth + tangential * -half_width, outer_top_l, frame_material)
	_frame_beam(radial * depth + tangential * half_width, outer_top_r, frame_material)
	_frame_beam(outer_top_l, outer_top_r, frame_material)
	var lintel_l := radial * depth + tangential * -aperture_half_width + Vector3.UP * aperture_height
	var lintel_r := radial * depth + tangential * aperture_half_width + Vector3.UP * aperture_height
	_frame_beam(radial * depth + tangential * -aperture_half_width, lintel_l, frame_material)
	_frame_beam(radial * depth + tangential * aperture_half_width, lintel_r, frame_material)
	_frame_beam(lintel_l, lintel_r, frame_material)
	return collision_faces

func _frame_beam(start: Vector3, end: Vector3, material: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.11
	mesh.bottom_radius = 0.11
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var y := (end - start).normalized()
	var helper := Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	instance.transform = Transform3D(Basis(x, y * start.distance_to(end), z), (start + end) * 0.5)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	# Godot front faces use clockwise winding.
	var ordered := [a, c, b] if (b - a).cross(c - a).dot(normal) > 0.0 else [a, b, c]
	for point: Vector3 in ordered:
		surface.set_normal(normal)
		surface.add_vertex(point)

func _add_mesh(mesh: Mesh, label: String, shadows: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
