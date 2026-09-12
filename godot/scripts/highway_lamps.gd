extends RefCounted
## Lamp stations use route arc length, so panel and tile boundaries do not
## change their spacing. All poles share one imported game-resolution mesh.
const SCENE := preload("res://assets/roads/lamp/industrial_lamp.glb")
const SPACING := 40.0
const HEIGHT := 12.0
static var shared_mesh: ArrayMesh
static var glow_mesh: BoxMesh
static var mounting_mesh: BoxMesh

static func layout(tiles: Dictionary, half_width: float, min_station_by_route: Dictionary = {}) -> Dictionary:
	var routes := {}
	for key in tiles:
		for segment: Dictionary in tiles[key]:
			if not routes.has(segment.route):
				routes[segment.route] = []
			routes[segment.route].append(segment)
	var result := {}
	for id in routes:
		var segments: Array = routes[id]
		segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)
		if segments[0].get("kind") == "junction":
			# Corner poles leave all four junction mouths clear.
			for s: Dictionary in [segments[0], segments[-1]]:
				var p: Vector3 = s.a if s.index == 0 else s.b
				for side: float in [-1.0, 1.0]:
					append_lamp(result, s, p, s.ra, side, float(s.half_width), 0.0, (segments[0].a + segments[-1].b) * 0.5)
			continue
		var min_station: float = min_station_by_route.get(id, 0.0)
		for side: float in [-1.0, 1.0]:
			var next := 10.0 if side < 0 else 30.0
			var traversed := 0.0
			for s: Dictionary in segments:
				var length: float = s.a.distance_to(s.b)
				while next < traversed + length:
					if next >= min_station:
						var t := (next - traversed) / length
						var p: Vector3 = s.a.lerp(s.b, t)
						var right: Vector3 = s.ra.lerp(s.rb, t).normalized()
						append_lamp(result, s, p, right, side, float(s.get("half_width", half_width)), next)
					next += SPACING
				traversed += length
	return result

static func append_lamp(output: Dictionary, segment: Dictionary, centre: Vector3, right: Vector3, side: float, width: float, station: float, aim: Vector3 = Vector3.INF) -> void:
	var inward := -right * side
	var basis := Basis(inward, Vector3.UP, inward.cross(Vector3.UP))
	var position := centre + right * side * (width + 0.7)
	var key := Vector2i(floori(segment.position.x / 64.0), floori(segment.position.z / 64.0))
	if not output.has(key):
		output[key] = []
	output[key].append({"transform": Transform3D(basis, position), "route": segment.route,
		"station": station, "side": side, "centre": centre, "width": width, "junction": segment.get("kind") == "junction", "aim": aim})

static func prepare() -> void:
	if shared_mesh != null:
		return
	shared_mesh = ArrayMesh.new()
	var root := SCENE.instantiate()
	collect(root, Transform3D.IDENTITY)
	root.free()
	glow_mesh = BoxMesh.new()
	glow_mesh.size = Vector3(1.05, 0.035, 0.5)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.88, 0.65)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.82, 0.52)
	glow.emission_energy_multiplier = 3.0
	glow_mesh.material = glow
	mounting_mesh = BoxMesh.new()
	mounting_mesh.size = Vector3(1.8, 0.5, 1.5)
	mounting_mesh.material = preload("res://assets/roads/concrete.tres")

static func collect(node: Node, parent_transform: Transform3D) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(node.mesh.surface_get_material(surface))
			st.append_from(node.mesh, surface, transform)
			st.commit(shared_mesh)
	for child in node.get_children():
		collect(child, transform)

static func light_position() -> Vector3:
	prepare()
	# The supplied arm extends along +X. Put light under its outer housing.
	var bounds := shared_mesh.get_aabb()
	return Vector3(bounds.end.x - 0.7, bounds.end.y - 0.35, bounds.get_center().z)

static func build(descriptors: Array, near: bool) -> Node3D:
	prepare()
	var root := Node3D.new()
	root.name = "HighwayLighting"
	root.set_meta("lamp_count", descriptors.size())
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = shared_mesh
	poles.instance_count = descriptors.size()
	var bulbs := MultiMesh.new()
	bulbs.transform_format = MultiMesh.TRANSFORM_3D
	bulbs.mesh = glow_mesh
	bulbs.instance_count = descriptors.size()
	var mounts := MultiMesh.new()
	mounts.transform_format = MultiMesh.TRANSFORM_3D
	mounts.mesh = mounting_mesh
	mounts.instance_count = descriptors.size()
	for i in descriptors.size():
		var transform: Transform3D = descriptors[i].transform
		poles.set_instance_transform(i, transform)
		bulbs.set_instance_transform(i, transform.translated_local(light_position()))
		mounts.set_instance_transform(i, transform.translated_local(Vector3(0.0, -0.25, 0.0)))
		if near:
			var light := SpotLight3D.new()
			light.name = "RoadLight_%d" % i
			light.position = transform * light_position()
			light.rotation.x = -PI * 0.5
			if descriptors[i].aim != Vector3.INF:
				light.basis = Basis.looking_at(descriptors[i].aim - light.position, Vector3.UP)
			light.light_color = Color(1.0, 0.88, 0.68)
			light.light_energy = 9.0
			light.spot_range = 70.0 if descriptors[i].junction else 32.0
			light.spot_angle = 55.0 if descriptors[i].junction else 65.0
			light.spot_attenuation = 1.2
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 85.0
			light.distance_fade_length = 45.0
			root.add_child(light)
	for multimesh in [poles, bulbs, mounts]:
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	return root
