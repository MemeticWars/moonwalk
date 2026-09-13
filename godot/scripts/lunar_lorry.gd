extends VehicleBody3D
# InPost logistics rover. A real rigid body: it carries momentum, its four
# VehicleWheel3D suspensions take up the ground softly, and it collides with the
# terrain mesh and the boulders for real. The decimated donor supplies the rolling
# chassis and the wheels; the textured GLB drops in as the cabin pod. One constant
# scales the whole visual rig — the body, its box collider and the wheels stay in
# world metres so physics never sees a scaled node.

const LORRY_SCENE := preload("res://assets/lorry/lunar_logistics_rover_decimated.glb")
const POD_SCENE := preload("res://assets/lorry/lunar_lorry_textured_body.glb")

# The decimated donor GLB imports at ~0.12 m (a Meshy.ai model, native scale is
# meaningless). This constant is the ONLY size knob: the suspension, wheel radius,
# hull collider and highway lane width are all measured off the scaled rig. Target
# a ~5.0 m long pressurised hauler -> 5.0 / 0.12003 donor length.
const ROVER_SCALE := 41.66
const CHASSIS_MESH := "mesh_13"
const CABIN_MESH := "mesh_12"
const WHEEL_NAMES := ["mesh_0", "mesh_5", "mesh_9", "mesh_10"]
const MAX_TRACK_MARKS := 240

const CRUISE_SPEED := 1.7           # m/s — a careful crawl over lunar dunes
const UPRIGHT_ASSIST := 9.0         # active suspension keeps the tall pod off its side
const ENGINE_PULL := 1500.0        # N
const REVERSE_PULL := 1100.0
const STEER_LIMIT := deg_to_rad(24.0)
const STEER_RATE := 2.0
const WAYPOINT_RADIUS := 6.0
const STUCK_SPEED := 0.3
const STUCK_TIME := 2.0

# Firm-but-supple suspension — a visible up/down give without the body wallowing.
const SUSPENSION_REST := 0.5
const SUSPENSION_TRAVEL := 0.38
const SUSPENSION_STIFFNESS := 28.0
const DAMP_COMPRESS := 3.6
const DAMP_RELAX := 4.8
const WHEEL_GRIP := 3.4
const WHEEL_ROLL_INFLUENCE := 0.04

var terrain: Node
var model: Node3D
var pod: Node3D
var vwheels: Array[VehicleWheel3D] = []
var wheels: Array[Node3D] = []            # visual tyre meshes, for track stamping and tests
var headlights: Array[SpotLight3D] = []
var track_root := Node3D.new()
var track_material: StandardMaterial3D
var track_instances: MultiMeshInstance3D
var track_multimesh: MultiMesh
var track_cursor := 0
var track_count := 0
var last_stamp := Vector3.INF
var light_mode := 1
var wheel_radius := 1.3
var rig_ready := false
var stuck_for := 0.0
var unstick_for := 0.0
var controlled := false
var drive_throttle := 0.0
var drive_steer := 0.0
var drive_brake := true
const LUNAR_GRAVITY := 1.62
const MAX_DRIVE_SPEED := 8.0
const REGOLITH_GRIP := 0.8

var route := PackedVector3Array([
	Vector3(11.0, 0.0, -22.0),
	Vector3(11.0, 0.0, 11.0),
	Vector3(-2.0, 0.0, 18.0),
	Vector3(-18.0, 0.0, 11.0),
	Vector3(-18.0, 0.0, -22.0),
	Vector3(-2.0, 0.0, -29.0),
])
var route_index := 1

func set_patrol_route(points: PackedVector3Array) -> void:
	# Route authoring lives with each colony. Keep the rover's suspension and
	# steering code independent from those location-specific patrol plans.
	if points.size() < 2:
		push_error("Lorry patrol route requires at least two points")
		return
	route = points
	route_index = 1

func _ready() -> void:
	name = "LunarLogisticsRover"
	mass = 2600.0
	collision_layer = 1
	collision_mask = 1
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0 # No aerodynamic drag in vacuum.
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM

	track_material = StandardMaterial3D.new()
	track_material.albedo_color = Color(0.13, 0.15, 0.17, 0.9)
	track_material.roughness = 1.0
	track_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	track_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_build_track_renderer()
	get_parent().add_child(track_root)
	track_root.name = "WheelTracks"

	_build_visuals()
	_build_headlights()
	set_light_mode(light_mode)
	global_position = _route_point(0)
	freeze = true
	call_deferred("_finish_rig")

func _build_visuals() -> void:
	model = LORRY_SCENE.instantiate()
	add_child(model)
	# Donor front (its -X) turned to face the body's forward (-Z).
	model.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	model.scale = Vector3.ONE * ROVER_SCALE
	_dress_donor(model)

	pod = POD_SCENE.instantiate()
	add_child(pod)
	pod.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	pod.scale = Vector3.ONE

func _wheel_mesh_names() -> Array:
	return WHEEL_NAMES

func _dress_donor(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var key := mesh.name.to_lower()
		if key == CHASSIS_MESH:
			var steel := StandardMaterial3D.new()
			steel.albedo_color = Color("3b3f45")
			steel.metallic = 0.55
			steel.roughness = 0.5
			mesh.material_override = steel
		elif key == CABIN_MESH:
			# The pod is an open shell; keep the donor cabin as a closed dark
			# backing so gaps in the pod read as interior, not sky.
			var shell := StandardMaterial3D.new()
			shell.albedo_color = Color("14161a")
			shell.roughness = 0.85
			shell.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.material_override = shell
		elif key in WHEEL_NAMES:
			var tyre := StandardMaterial3D.new()
			tyre.albedo_color = Color("191b1f")
			tyre.roughness = 0.97
			mesh.material_override = tyre
		else:
			mesh.visible = false
	for child in node.get_children():
		_dress_donor(child)

func _finish_rig() -> void:
	# Seat the body on the ground (origin at the wheel-contact plane) and aim it
	# down the route before the wheels and collider are measured against it.
	global_transform = Transform3D(Basis(Vector3.UP, _heading_to(_route_point(1))), _seated_origin(_route_point(0)))
	_fit_pod()
	_build_suspension()
	_place_collider_and_mass()
	freeze = false
	rig_ready = true

func _fit_pod() -> void:
	var cabin_mesh := _named(model, CABIN_MESH)
	var cabin := _combined_aabb([cabin_mesh])
	var raw := _combined_aabb(_all_meshes(pod))
	if raw.size.z > 0.0:
		pod.scale = Vector3.ONE * (cabin.size.z / raw.size.z)
	var fitted := _combined_aabb(_all_meshes(pod))
	pod.global_position += cabin.get_center() - fitted.get_center()
	_disable_shadows(pod)
	var c := cabin.get_center()
	var t := cabin_mesh.global_transform
	cabin_mesh.global_transform = Transform3D(t.basis.scaled(Vector3.ONE * 0.95), c + (t.origin - c) * 0.95)

func _build_suspension() -> void:
	var donor_wheels := {}
	for m in _all_meshes(model):
		if m.name.to_lower() in _wheel_mesh_names():
			donor_wheels[m.name.to_lower()] = m
	for key in _wheel_mesh_names():
		var tyre: MeshInstance3D = donor_wheels[key]
		var centre := tyre.global_transform * tyre.mesh.get_aabb().get_center()
		var box := _combined_aabb([tyre])
		wheel_radius = box.size.y * 0.5

		var axle_local := to_local(centre)
		var vw := VehicleWheel3D.new()
		vw.name = "Wheel_" + key
		vw.position = axle_local + Vector3(0.0, SUSPENSION_REST, 0.0)
		add_child(vw)
		vw.use_as_traction = true
		vw.use_as_steering = axle_local.z < 0.0     # front axle steers
		vw.wheel_radius = wheel_radius
		vw.wheel_rest_length = SUSPENSION_REST
		vw.wheel_friction_slip = REGOLITH_GRIP
		vw.wheel_roll_influence = WHEEL_ROLL_INFLUENCE
		vw.suspension_travel = SUSPENSION_TRAVEL
		vw.suspension_stiffness = SUSPENSION_STIFFNESS
		vw.suspension_max_force = mass * LUNAR_GRAVITY * 3.0 / _wheel_mesh_names().size()
		vw.damping_compression = DAMP_COMPRESS
		vw.damping_relaxation = DAMP_RELAX
		vwheels.append(vw)

		tyre.reparent(vw, true)
		# Centre the tyre mesh on the wheel node so it rolls about its own axle.
		tyre.position -= tyre.transform * tyre.mesh.get_aabb().get_center()
		wheels.append(tyre)
	_stamp_tracks()

func _place_collider_and_mass() -> void:
	# The box wraps the hull but never reaches down into the wheels' zone — the
	# VehicleWheel3D rays own ground contact, the box only stops the rover against
	# walls and boulders at body height.
	var hull := _combined_aabb([_named(model, CHASSIS_MESH), _named(model, CABIN_MESH)])
	var floor_y := maxf(hull.position.y, global_position.y + wheel_radius * 2.0 + 0.3)
	var shape := BoxShape3D.new()
	shape.size = Vector3(hull.size.x * 0.9, hull.end.y - floor_y, hull.size.z * 0.92)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	col.global_position = Vector3(hull.get_center().x, (floor_y + hull.end.y) * 0.5, hull.get_center().z)
	# Weight sits at axle height over the chassis so the tall pod does not roll it.
	var chassis := _combined_aabb([_named(model, CHASSIS_MESH)])
	center_of_mass = to_local(Vector3(chassis.get_center().x, chassis.position.y, chassis.get_center().z))

func _seated_origin(where: Vector3) -> Vector3:
	# Drop the rover in a hair above the ground and let the suspension take it up.
	var ground := where.y
	if terrain != null:
		ground = terrain.height_at(where.x, where.z)
	return Vector3(where.x, ground + 0.4, where.z)

func _heading_to(point: Vector3) -> float:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length() < 0.01:
		return rotation.y
	return atan2(-flat.x, -flat.z)

func _route_point(offset: int) -> Vector3:
	var p := route[(route_index + offset) % route.size()]
	if terrain != null:
		p.y = terrain.height_at(p.x, p.z)
	return p

func _build_headlights() -> void:
	for x in [-1.26, 1.26]:
		var lamp := SpotLight3D.new()
		lamp.name = "HeadlightLeft" if x < 0 else "HeadlightRight"
		lamp.position = Vector3(x * ROVER_SCALE * 0.03, wheel_radius + 1.2, -ROVER_SCALE * 0.055)
		lamp.light_color = Color(1.0, 0.91, 0.72)
		lamp.shadow_enabled = false
		add_child(lamp)
		headlights.append(lamp)

func set_light_mode(mode: int) -> void:
	light_mode = posmod(mode, 3)
	for lamp in headlights:
		lamp.visible = light_mode != 0
		lamp.light_energy = 3.8 if light_mode == 1 else 8.5
		lamp.spot_range = 28.0 if light_mode == 1 else 82.0
		lamp.spot_angle = 36.0 if light_mode == 1 else 21.0

func light_mode_label() -> String:
	return ["wyłączone", "krótkie", "długie"][light_mode]

func _physics_process(delta: float) -> void:
	if not rig_ready:
		return
	if controlled:
		_drive(delta)
		return
	var goal := _route_point(1)
	var to_goal := goal - global_position
	to_goal.y = 0.0
	if to_goal.length() < WAYPOINT_RADIUS:
		route_index = (route_index + 1) % route.size()
		goal = _route_point(1)
		to_goal = goal - global_position
		to_goal.y = 0.0

	var forward := -global_transform.basis.z
	var speed := linear_velocity.dot(forward)
	var want := to_goal.normalized()
	var steer_error := forward.signed_angle_to(want, Vector3.UP)
	steering = move_toward(steering, clampf(steer_error, -STEER_LIMIT, STEER_LIMIT), STEER_RATE * delta)

	var contacts := 0
	for vw in vwheels:
		if vw.is_in_contact():
			contacts += 1

	# Stuck detection — a boulder in the way, or a wall of terrain.
	if absf(speed) < STUCK_SPEED and contacts >= 2 and unstick_for <= 0.0:
		stuck_for += delta
		if stuck_for > STUCK_TIME:
			unstick_for = 1.2
	else:
		stuck_for = 0.0

	if unstick_for > 0.0:
		unstick_for -= delta
		engine_force = -REVERSE_PULL
		steering = -steering
		brake = 0.0
	elif contacts == 0:
		# Airborne off a crest — coast, don't spin the wheels up.
		engine_force = 0.0
		brake = 0.0
	elif speed < CRUISE_SPEED:
		engine_force = ENGINE_PULL
		brake = 0.0
	elif speed < CRUISE_SPEED + 0.6:
		engine_force = 0.0
		brake = 1.5
	else:
		engine_force = 0.0
		brake = 9.0

	# Active-suspension upright assist: a soft torque back toward level while the
	# wheels have the ground, so the tall pod leans into a slope but never lies down.
	if contacts >= 2:
		var lean := global_transform.basis.y.cross(Vector3.UP)   # axis * sin(tilt)
		if lean.length() > 0.03:
			apply_torque(lean * mass * UPRIGHT_ASSIST - Vector3(angular_velocity.x, 0.0, angular_velocity.z) * mass * 0.8)

	if last_stamp == Vector3.INF or global_position.distance_to(last_stamp) >= 1.2:
		_stamp_tracks()

func _stamp_tracks() -> void:
	if wheels.is_empty() or terrain == null:
		return
	last_stamp = global_position
	for vw in vwheels:
		if not vw.is_in_contact():
			continue
		var p := vw.global_position
		var local_p := track_root.to_local(Vector3(p.x, terrain.height_at(p.x, p.z) + 0.05, p.z))
		var basis := Basis(Vector3.UP, rotation.y)
		track_multimesh.set_instance_transform(track_cursor, Transform3D(basis, local_p))
		track_cursor = (track_cursor + 1) % MAX_TRACK_MARKS
		track_count += 1
	track_multimesh.visible_instance_count = mini(track_count, MAX_TRACK_MARKS)

func _drive(delta: float) -> void:
	var contacts := 0
	for wheel in vwheels:
		if wheel.is_in_contact():
			contacts += 1
	var speed := linear_velocity.dot(-global_basis.z)
	var speed_limit := MAX_DRIVE_SPEED if drive_throttle >= 0 else 2.5
	# Limit lateral acceleration to the traction available at lunar weight.
	var limit := minf(STEER_LIMIT, atan(REGOLITH_GRIP * LUNAR_GRAVITY * 3.5 / maxf(speed * speed, 0.1)))
	steering = move_toward(steering, drive_steer * limit, delta * 0.6)
	var traction := mass * LUNAR_GRAVITY * REGOLITH_GRIP * float(contacts) / maxf(vwheels.size(), 1)
	var reverse_requested := drive_throttle * speed < -0.2
	engine_force = 0.0
	brake = 0.0
	if contacts > 0:
		if drive_brake or reverse_requested:
			brake = traction / maxf(vwheels.size(), 1)
		elif absf(speed) < speed_limit:
			# VehicleBody's positive engine direction is +Z; this model faces -Z.
			engine_force = -drive_throttle * minf(ENGINE_PULL, traction) / maxf(vwheels.size(), 1)
		# Rolling resistance acts only on the ground, never as airborne drag.
		var horizontal := Vector3(linear_velocity.x, 0, linear_velocity.z)
		if horizontal.length() > 0.01:
			apply_central_force(-horizontal.normalized() * minf(mass * LUNAR_GRAVITY * 0.025, horizontal.length() * mass / delta))
	if last_stamp == Vector3.INF or global_position.distance_to(last_stamp) >= 1.2:
		_stamp_tracks()

func _build_track_renderer() -> void:
	var strip := PlaneMesh.new()
	strip.size = Vector2(1.6, 2.6)
	strip.material = track_material
	track_multimesh = MultiMesh.new()
	track_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	track_multimesh.instance_count = MAX_TRACK_MARKS
	track_multimesh.visible_instance_count = 0
	track_multimesh.mesh = strip
	track_instances = MultiMeshInstance3D.new()
	track_instances.name = "BatchedWheelMarks"
	track_instances.multimesh = track_multimesh
	track_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track_root.add_child(track_instances)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_L:
		set_light_mode(light_mode + 1)

func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_all_meshes(child))
	return result

func _named(root: Node, lower_name: String) -> MeshInstance3D:
	for mesh in _all_meshes(root):
		if mesh.name.to_lower() == lower_name:
			return mesh
	return null

func _combined_aabb(meshes: Array) -> AABB:
	var result := AABB()
	var seeded := false
	for mesh: MeshInstance3D in meshes:
		if mesh == null or mesh.mesh == null:
			continue
		var local: AABB = mesh.mesh.get_aabb()
		for i in 8:
			var p: Vector3 = mesh.global_transform * local.get_endpoint(i)
			if not seeded:
				result = AABB(p, Vector3.ZERO)
				seeded = true
			else:
				result = result.expand(p)
	return result

func _disable_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)


static func highway_vehicle_width() -> float:
	# Donor longitudinal axis is X; after the rig's turn Z becomes width.
	var donor := LORRY_SCENE.instantiate()
	var bounds := _asset_bounds(donor, Transform3D.IDENTITY, true)
	var cabin := _asset_bounds(donor, Transform3D.IDENTITY, true, CABIN_MESH)
	var cabin_width := cabin.size.z * ROVER_SCALE
	var pod_model := POD_SCENE.instantiate()
	var pod_bounds := _asset_bounds(pod_model, Transform3D.IDENTITY, false)
	if pod_bounds.size.x > 0:
		cabin_width = maxf(cabin_width, pod_bounds.size.z * cabin.size.x * ROVER_SCALE / pod_bounds.size.x)
	donor.free()
	pod_model.free()
	return maxf(bounds.size.z * ROVER_SCALE, cabin_width)

static func _asset_bounds(node: Node, parent_transform: Transform3D, donor: bool, only: String = "") -> AABB:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	var bounds := AABB()
	if node is MeshInstance3D and node.mesh != null:
		var key := node.name.to_lower()
		if (not donor or key in WHEEL_NAMES or key == CHASSIS_MESH or key == CABIN_MESH) and (only.is_empty() or only == key):
			bounds = transform * node.mesh.get_aabb()
	for child in node.get_children():
		var child_bounds := _asset_bounds(child, transform, donor, only)
		if child_bounds.size != Vector3.ZERO:
			bounds = child_bounds if bounds.size == Vector3.ZERO else bounds.merge(child_bounds)
	return bounds
