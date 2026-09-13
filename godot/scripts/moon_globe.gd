extends Node3D

signal local_surface_requested(coordinates: Vector2)

var terrain: Node3D
var roads: Node                    # RoadStreamer — the baked highway network
var actor: Node3D                  # Agnes on foot
var convoy: Node3D                 # the logistics rover
var camera := Camera3D.new()
var moon := Node3D.new()
var yaw := 0.0
var pitch := -0.18
var distance := 4.1
const MIN_ORBIT_DISTANCE := 1.018
const MAX_ORBIT_DISTANCE := 40.0
const RADIUS_M := 1737400.0
var meso: Node3D
var approach := false
const ORBIT_LODS := [[128, 64], [256, 128], [512, 256]]
# Orbit and local terrain use the same physical vertical scale.
const ORBIT_VERTICAL_EXAGGERATION := 1.0
var moon_lods: Array[MeshInstance3D] = []
var active_lod := -1
var surface_transition_sent := false
var markers: Array[Node3D] = []
var colony_data: Dictionary

# Geographic anchor of the active walking sector.
var sector_anchor := Vector2(-82.0, 30.0)
var highways: MeshInstance3D
var actor_dot: MeshInstance3D
var convoy_dot: MeshInstance3D
var live_labels: Array[Label3D] = []

func _ready() -> void:
	position = Vector3(0, 10000, 0)
	add_child(moon)
	meso = preload("res://scripts/lunar_orbit_lod.gd").new()
	meso.terrain = terrain
	moon.add_child(meso)
	for lod in ORBIT_LODS:
		moon_lods.append(_build_moon_lod(lod[0], lod[1]))
	_update_lod()
	colony_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/colonies.json"))
	for colony: Dictionary in colony_data.locations:
		var marker := MeshInstance3D.new()
		var dot := SphereMesh.new()
		dot.radius = 0.008
		dot.height = 0.016
		marker.mesh = dot
		var color := StandardMaterial3D.new()
		color.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		color.albedo_color = Color("f5be61")
		marker.material_override = color
		moon.add_child(marker)
		marker.position = geo(colony.latitude, colony.longitude) * 1.014
		var label := Label3D.new()
		label.text = colony.name
		label.font_size = 36
		label.pixel_size = 0.0011
		label.position = marker.position * 1.035
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("f5d396")
		moon.add_child(label)
		markers.append(label)
	_build_highways()
	_build_live_units()
	add_child(camera)
	camera.near = 0.005
	camera.far = 80
	camera.fov = 42
	_update_camera()

func _build_moon_lod(cols: int, rows: int) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for y in rows + 1:
		for x in cols + 1:
			var lat := 90.0 - y * 180.0 / rows
			var lon := x * 360.0 / cols - 180.0
			var normal := geo(lat, lon)
			var elevation: float = terrain.coarse_elevation(lat, lon)
			vertices.append(normal * (1.0 + elevation * ORBIT_VERTICAL_EXAGGERATION / 1737400.0))
			normals.append(normal)
			uvs.append(Vector2(float(x) / cols, float(y) / rows))
			colors.append(_height_color(elevation))
	for y in rows:
		for x in cols:
			var a := y * (cols + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + cols + 1, a + 1, a + cols + 2, a + cols + 1]))
	# Normals follow the DEM, including the coarsest globe, rather than a smooth sphere.
	for y in range(1, rows):
		for x in cols + 1:
			var a := y*(cols+1)+x
			var east := vertices[y*(cols+1)+posmod(x+1,cols)]-vertices[y*(cols+1)+posmod(x-1,cols)]
			var south := vertices[a+cols+1]-vertices[a-cols-1]
			normals[a] = south.cross(east).normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "MoonLOD_%dx%d" % [cols, rows]
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = false
	mat.albedo_texture = preload("res://scripts/lunar_regional_color.gd").get_texture()
	mat.albedo_color = Color.WHITE
	mat.roughness = 1
	instance.material_override = mat
	moon.add_child(instance)
	return instance

func _height_color(elevation: float) -> Color:
	# Relative to the 1737.4 km lunar reference sphere: deep mare/crater floors
	# are blue-grey; average highlands are warm grey; the highest rims are pale.
	var t := clampf((elevation + 7500.0) / 14500.0, 0.0, 1.0)
	if t < 0.42:
		return Color("21344a").lerp(Color("607080"), t / 0.42)
	if t < 0.72:
		return Color("607080").lerp(Color("a18f78"), (t - 0.42) / 0.30)
	return Color("a18f78").lerp(Color("eee6d8"), (t - 0.72) / 0.28)

func _update_lod() -> void:
	if meso != null and meso.ready_for_view and distance < 1.4:
		for instance in moon_lods: instance.visible = false
		active_lod = -1
		return
	var next := 0 if distance > 8.0 else (1 if distance > 2.4 else 2)
	if next == active_lod and not moon_lods.is_empty():
		return
	active_lod = next
	for i in moon_lods.size():
		moon_lods[i].visible = i == active_lod

func geo(lat: float, lon: float) -> Vector3:
	return Vector3(cos(deg_to_rad(lat)) * sin(deg_to_rad(lon)), sin(deg_to_rad(lat)), cos(deg_to_rad(lat)) * cos(deg_to_rad(lon)))

func sector_geo(world_x: float, world_z: float) -> Vector3:
	# Use real coordinates for all landing sites, on either lunar hemisphere.
	var ll: Vector2 = terrain.latlon_at(world_x, world_z)
	return geo(ll.x, ll.y)

func _build_highways() -> void:
	if roads == null or roads.world_routes.is_empty():
		return
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("74d8ff")
	for route: Dictionary in roads.world_routes:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for point: Dictionary in route.points:
			mesh.surface_add_vertex(geo(point.latitude, point.longitude) * 1.012)
		mesh.surface_end()
	highways = MeshInstance3D.new()
	highways.name = "LunarHighways"
	highways.mesh = mesh
	highways.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.add_child(highways)

func _build_live_units() -> void:
	actor_dot = _unit_dot(Color("7fe9ff"), 0.011)
	convoy_dot = _unit_dot(Color("ff9647"), 0.014)
	moon.add_child(actor_dot)
	moon.add_child(convoy_dot)
	for pair in [["Agnes", Color("c8f2ff")], ["Konwój", Color("ffd3ac")]]:
		var l := Label3D.new()
		l.text = pair[0]
		l.font_size = 26
		l.pixel_size = 0.0009
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = pair[1]
		l.outline_size = 6
		l.outline_modulate = Color(0, 0, 0, 0.85)
		moon.add_child(l)
		live_labels.append(l)

func _unit_dot(color: Color, radius: float) -> MeshInstance3D:
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	dot.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	dot.material_override = mat
	return dot

func _process(_delta: float) -> void:
	if not visible:
		return
	if approach:
		var active_camera := get_viewport().get_camera_3d()
		meso.update_view(to_local(active_camera.global_position), _delta)
		_update_lod()
		return
	var radial := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var yaw_input := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var pitch_input := Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down")
	if radial != 0.0:
		distance = clampf(1.0 + (distance - 1.0) * exp(-radial * _delta * 0.8), MIN_ORBIT_DISTANCE, MAX_ORBIT_DISTANCE)
	if yaw_input != 0.0:
		yaw -= yaw_input * _delta * 1.25
	if pitch_input != 0.0:
		pitch = clampf(pitch + pitch_input * _delta * 0.8, -PI * 0.5 + 0.00001, PI * 0.5 - 0.00001)
	_update_lod()
	_update_camera()
	meso.visible = distance < 1.4
	if meso.visible:
		meso.update_view(camera.position, _delta)
	# Any selected point can start the continuous meso approach.
	if not surface_transition_sent and distance <= 1.045:
		surface_transition_sent = true
		local_surface_requested.emit(target_coordinates())
		return
	_place_unit(actor_dot, live_labels[0] if live_labels.size() > 0 else null, actor)
	_place_unit(convoy_dot, live_labels[1] if live_labels.size() > 1 else null, convoy)
	var facing := geo(sector_anchor.x, sector_anchor.y).normalized().dot(camera.position.normalized())
	for l in live_labels:
		l.visible = l.position.length() > 0.01 and facing > 0.1
	actor_dot.visible = actor_dot.position.length() > 0.01 and facing > 0.1
	convoy_dot.visible = convoy_dot.position.length() > 0.01 and facing > 0.1

func _place_unit(dot: MeshInstance3D, label: Label3D, node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		dot.position = Vector3.ZERO
		return
	var here := sector_geo(node.global_position.x, node.global_position.z)
	dot.position = here * 1.016
	if label != null:
		# Push the two labels out to different radii so they never stack up.
		label.position = here * (1.11 if label.text == "Agnes" else 1.24)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.006, -PI * 0.5 + 0.00001, PI * 0.5 - 0.00001)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(MIN_ORBIT_DISTANCE, 1.0 + (distance - 1.0) * 0.82)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(MAX_ORBIT_DISTANCE, 1.0 + (distance - 1.0) / 0.82)
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		_focus_active_sector()
	_update_lod()
	_update_camera()

func _focus_active_sector() -> void:
	var focus := geo(sector_anchor.x, sector_anchor.y)
	yaw = atan2(focus.x, focus.z)
	pitch = asin(focus.y)
	surface_transition_sent = false

func target_coordinates() -> Vector2:
	return Vector2(rad_to_deg(pitch), wrapf(rad_to_deg(yaw), -180.0, 180.0))

func _is_over_active_sector() -> bool:
	var radial := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return radial.dot(geo(sector_anchor.x, sector_anchor.y)) > 0.998

func _update_camera() -> void:
	camera.position = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(global_position, Vector3.FORWARD if approach else Vector3.UP)
	if approach:
		return
	for marker in markers:
		marker.visible = marker.position.normalized().dot(camera.position.normalized()) > 0.25

func begin_surface_frame(source: Node3D) -> void:
	# Same camera projection in metres, with the landing site's tangent origin.
	# No fade, teleport of the view, or change in apparent Moon size.
	terrain = source
	approach = true
	var lat: float = deg_to_rad(source.anchor_lat)
	var lon: float = deg_to_rad(source.anchor_lon)
	var up := geo(source.anchor_lat, source.anchor_lon)
	var east := Vector3(cos(lon), 0, -sin(lon))
	var south := Vector3(sin(lat)*sin(lon), -cos(lat), sin(lat)*cos(lon))
	var frame := Basis(east, up, south).transposed()
	transform = Transform3D(frame.scaled(Vector3.ONE * RADIUS_M), Vector3(0,-RADIUS_M-source.base_elevation,0))
	camera.near = 10.0
	camera.far = 8000000.0
	meso.reset_for_surface(source)
	meso.visible = true
	for child in moon.get_children():
		if child != meso and not (child is MeshInstance3D and moon_lods.has(child)): child.visible = false
	_update_camera()

static func surface_basis(coordinates: Vector2) -> Basis:
	var lat := deg_to_rad(coordinates.x)
	var lon := deg_to_rad(coordinates.y)
	return Basis(Vector3(cos(lon),0,-sin(lon)),Vector3(cos(lat)*sin(lon),sin(lat),cos(lat)*cos(lon)),Vector3(sin(lat)*sin(lon),-cos(lat),sin(lat)*cos(lon)))

func reset_orbit_frame() -> void:
	approach = false
	transform = Transform3D(Basis.IDENTITY, Vector3(0,10000,0))
	camera.near = 0.00001
	camera.far = 80.0
	meso.local_frame = false
	meso.detail_blend = 0.0
	meso.reference_radius = 1.0
	meso.local_hole = Vector4.ZERO
	meso.terrain = terrain
	for patch in meso.patches.values(): patch.queue_free()
	meso.patches.clear()
	meso.planned_view = Vector3.INF
	meso.ready_for_view = false
	for child in moon.get_children(): child.visible = true
	active_lod = -1
	_update_lod()
