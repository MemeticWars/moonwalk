extends Node3D
## One shared 6 m city-lamp mesh; individual bulbs only illuminate the close streets.
const SCENE := preload("res://assets/colonies/tycho/modules/street-lamp.glb")
const HEIGHT_M := 6.0
const SPACING_M := 18.0
const LIGHT_OFFSET := Vector3(0.0, HEIGHT_M - 0.175, 0.9)
const DIFFUSER_ROTATION := PI
const DIFFUSER_SIZE := Vector3(0.205, 0.045, 0.76)

func _ready() -> void:
	name = "CityStreetLamps"
	var mesh := _merged_mesh()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("303a42")
	material.metallic = 0.75
	material.roughness = 0.34
	mesh.surface_set_material(0, material)
	var stations := _stations()
	set_meta("lamp_count", stations.size())
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = stations.size()
	for i in stations.size():
		var lamp: Dictionary = stations[i]
		multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, lamp.yaw), Vector3(lamp.point.x, 0, lamp.point.y)))
	var poles := MultiMeshInstance3D.new()
	poles.name = "StreetLampPoles"
	poles.multimesh = multimesh
	add_child(poles)
	# Flat rectangular diffuser, one metre out from the central support pipe.
	var glow_mesh := BoxMesh.new()
	# Half the former width, then turned ninety degrees so the narrow edge faces
	# along the lamp arm on every street orientation.
	glow_mesh.size = DIFFUSER_SIZE
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = Color(1.0, 0.82, 0.48)
	glow_material.emission_enabled = true
	glow_material.emission = Color(1.0, 0.68, 0.25)
	glow_material.emission_energy_multiplier = 2.0
	glow_mesh.material = glow_material
	var bulbs := MultiMesh.new()
	bulbs.transform_format = MultiMesh.TRANSFORM_3D
	bulbs.mesh = glow_mesh
	bulbs.instance_count = stations.size()
	for i in stations.size():
		var lamp: Dictionary = stations[i]
		# Offset from the pole in its arm direction first; rotate only the flat
		# diffuser around its own centre so the offset never flips backwards.
		var pole_transform := Transform3D(Basis(Vector3.UP, lamp.yaw), Vector3(lamp.point.x, 0, lamp.point.y))
		var bulb_transform := pole_transform.translated_local(LIGHT_OFFSET)
		bulb_transform.basis = pole_transform.basis * Basis(Vector3.UP, DIFFUSER_ROTATION)
		bulbs.set_instance_transform(i, bulb_transform)
	var bulbs_instance := MultiMeshInstance3D.new()
	bulbs_instance.name = "StreetLampBulbs"
	bulbs_instance.multimesh = bulbs
	bulbs_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulbs_instance)
	for i in stations.size():
		var lamp: Dictionary = stations[i]
		var light := SpotLight3D.new()
		light.name = "StreetLight_%02d" % i
		var transform := Transform3D(Basis(Vector3.UP, lamp.yaw), Vector3(lamp.point.x, 0, lamp.point.y))
		light.position = transform * (LIGHT_OFFSET - Vector3(0.0, 0.06, 0.0))
		light.light_color = Color(1.0, 0.77, 0.48)
		light.light_energy = 1.6
		light.spot_range = 16.0
		light.spot_angle = 58.0
		light.spot_attenuation = 1.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 55.0
		light.distance_fade_length = 35.0
		add_child(light)
		light.look_at(to_global(transform * Vector3(0.0, 0.0, 4.5)), Vector3.UP)

func _stations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Long entrance axis, then the C's cross street and both inner sidewalks.
	_append_line(result, Vector2(-6, -91), Vector2(-6, 31), PI * 0.5)
	_append_line(result, Vector2(6, -91), Vector2(6, 31), -PI * 0.5)
	_append_line(result, Vector2(-29, 4), Vector2(29, 4), 0.0)
	_append_line(result, Vector2(-27, -34), Vector2(-27, 25), -PI * 0.5)
	_append_line(result, Vector2(27, -34), Vector2(27, 25), PI * 0.5)
	return result

func _append_line(result: Array[Dictionary], start: Vector2, finish: Vector2, yaw: float) -> void:
	var length := start.distance_to(finish)
	var count := floori(length / SPACING_M)
	for i in range(1, count + 1):
		var point := start.lerp(finish, float(i) / (count + 1))
		# Do not crowd the central-house or street intersections.
		if point.distance_to(Vector2(0, 35)) < 27.0 or point.distance_to(Vector2(0, 4)) < 6.0:
			continue
		result.append({"point": point, "yaw": yaw})

func _merged_mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	var root := SCENE.instantiate()
	_collect(root, Transform3D.IDENTITY, result)
	root.free()
	return result

func _collect(node: Node, parent: Transform3D, output: ArrayMesh) -> void:
	var transform := parent
	if node is Node3D:
		transform *= (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var builder := SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builder.append_from(instance.mesh, surface, transform)
			builder.commit(output)
	for child in node.get_children():
		_collect(child, transform, output)
