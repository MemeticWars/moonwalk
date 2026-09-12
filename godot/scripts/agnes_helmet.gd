extends Node3D

var visor := MeshInstance3D.new()
var visor_material := ShaderMaterial.new()

static func attach(visual: Node3D) -> Node3D:
	var skeleton := visual.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head := skeleton.find_bone("Head")
	assert(head >= 0, "Agnes needs the Head bone for her helmet")
	var binding := BoneAttachment3D.new()
	binding.name = "HelmetAttachment"
	binding.bone_name = "Head"
	skeleton.add_child(binding)
	var helmet: Node3D = (load("res://scripts/agnes_helmet.gd") as GDScript).new()
	helmet.name = "Helmet"
	binding.add_child(helmet)
	var skeleton_in_visual := visual.global_transform.affine_inverse() * skeleton.global_transform
	var head_rest := skeleton_in_visual * skeleton.get_bone_global_rest(head)
	var fit := Transform3D(Basis.from_scale(Vector3(0.20, 0.195, 0.21)), Vector3(0, 1.58, 0.0))
	# Match the 10% head reduction around the original head joint, then take the
	# shell in another 10% and settle it forward and down, so the face sits deeper
	# in the dome instead of pressing on the visor.
	fit.origin = head_rest.origin + (fit.origin - head_rest.origin) * 0.9
	fit.basis = fit.basis.scaled(Vector3.ONE * 0.81)
	fit.origin += Vector3(0.0, -0.01, 0.016)
	helmet.transform = head_rest.affine_inverse() * fit
	return helmet

func _ready() -> void:
	var shell := (load("res://assets/agnes/helmet_fitted.glb") as PackedScene).instantiate()
	add_child(shell)
	for mesh: MeshInstance3D in shell.find_children("*", "MeshInstance3D", true, false):
		var source := mesh.get_active_material(0) as StandardMaterial3D
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/helmet_shell.gdshader")
		material.set_shader_parameter("albedo_map", source.albedo_texture)
		material.set_shader_parameter("normal_map", source.normal_texture)
		mesh.material_override = material
	visor.name = "Visor"
	visor.mesh = _visor_mesh()
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visor_material.shader = preload("res://shaders/helmet_visor.gdshader")
	visor.material_override = visor_material
	add_child(visor)
	set_shade(0.0)

func set_shade(amount: float) -> void:
	visor_material.set_shader_parameter("shade", clampf(amount, 0.0, 1.0))

func _visor_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	const RINGS = 16
	const SEGMENTS = 64
	const HALF_WIDTH := 0.64
	const HALF_HEIGHT := 0.61
	const DEPTH := 0.31  # dome reach forward of the face; the rim (angle = PI/2) stays put
	for ring in RINGS + 1:
		var angle := float(ring) / RINGS * PI * 0.5
		for segment in SEGMENTS + 1:
			var theta := float(segment) / SEGMENTS * TAU
			var p := Vector3(HALF_WIDTH * sin(angle) * signf(cos(theta)) * pow(absf(cos(theta)), 0.65), HALF_HEIGHT * sin(angle) * signf(sin(theta)) * pow(absf(sin(theta)), 0.65), DEPTH * cos(angle))
			vertices.append(p + Vector3(0, -0.07, 0.61))
			normals.append((p / Vector3(HALF_WIDTH * HALF_WIDTH, HALF_HEIGHT * HALF_HEIGHT, DEPTH * DEPTH)).normalized())
	for ring in RINGS:
		for segment in SEGMENTS:
			var a := ring * (SEGMENTS + 1) + segment
			var b := a + SEGMENTS + 1
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
