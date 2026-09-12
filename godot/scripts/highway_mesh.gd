extends RefCounted
## Swept concrete and steel assets. Adjacent panels reuse exact edge positions
## and normals; the same surface supplies physics at both streaming LODs.
const CONCRETE := preload("res://assets/roads/concrete.tres")
const STEEL := preload("res://assets/roads/steel.tres")
const THICKNESS := 0.7

static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3) -> void:
	for item in [[a, na], [c, nb], [b, na], [b, na], [c, nb], [d, nb]]:
		st.set_normal(item[1])
		st.add_vertex(item[0])

static func deck(segments: Array, half_width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(CONCRETE)
	for s: Dictionary in segments:
		var a: Vector3 = s.a
		var b: Vector3 = s.b
		var width := float(s.get("half_width", half_width))
		var ra: Vector3 = s.ra * width
		var rb: Vector3 = s.rb * width
		quad(st, a - ra, a + ra, b - rb, b + rb, s.na, s.nb)
		var down := Vector3.DOWN * THICKNESS
		quad(st, a + ra, a + ra + down, b + rb, b + rb + down, s.ra, s.rb)
		quad(st, a - ra + down, a - ra, b - rb + down, b - rb, -s.ra, -s.rb)
		quad(st, a + ra + down, a - ra + down, b + rb + down, b - rb + down, Vector3.DOWN, Vector3.DOWN)
	var mesh := st.commit()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.86, 0.85, 0.72)
	paint.roughness = 0.92
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(paint)
	for s: Dictionary in segments:
		if not s.get("paint", true):
			continue
		var width := float(s.get("half_width", half_width))
		for lateral in [-width + 0.4, 0.0, width - 0.4]:
			if lateral == 0.0 and int(s.index) % 4 >= 2:
				continue
			var a: Vector3 = s.a + Vector3.UP * 0.015 + s.ra * lateral
			var b: Vector3 = s.b + Vector3.UP * 0.015 + s.rb * lateral
			quad(st, a - s.ra * 0.07, a + s.ra * 0.07, b - s.rb * 0.07, b + s.rb * 0.07, s.na, s.nb)
	st.commit(mesh)
	return mesh

static func beam(parent: Node3D, a: Vector3, b: Vector3, width: float, material: Material) -> void:
	if a.distance_to(b) < 0.01:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, a.distance_to(b), width)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = (a + b) * 0.5
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.1:
		side = up.cross(Vector3.RIGHT).normalized()
	instance.basis = Basis(side, up, side.cross(up))
	parent.add_child(instance)

static func fittings(parent: Node3D, s: Dictionary, half_width: float, near: bool) -> void:
	for sign_value in ([-1.0, 1.0] if s.get("rails", true) else []):
		var a: Vector3 = s.a + s.ra * half_width * sign_value
		var b: Vector3 = s.b + s.rb * half_width * sign_value
		for height in [0.45, 1.05]:
			beam(parent, a + Vector3.UP * height, b + Vector3.UP * height, 0.10, STEEL)
		if near:
			beam(parent, a, a + Vector3.UP * 1.15, 0.12, STEEL)
	if int(s.index) % 8 == 4 and s.clearance > 1.4:
		var top: Vector3 = s.position - Vector3.UP * THICKNESS
		beam(parent, top, top - Vector3.UP * (s.clearance - THICKNESS), 0.8, CONCRETE)
		var shoulder: Vector3 = (s.ra + s.rb).normalized() * half_width * 0.8
		beam(parent, top - Vector3.UP * 0.45 - shoulder, top - Vector3.UP * 0.45 + shoulder, 0.9, CONCRETE)
