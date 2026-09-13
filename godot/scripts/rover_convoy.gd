extends Node
## Owns boarding, camera, player inputs and breadcrumb navigation for drones.
const Truck := preload("res://scripts/lunar_truck.gd")
var game: Node
var rover: VehicleBody3D
var actor: CharacterBody3D
var driving := false
var trucks: Array[VehicleBody3D] = []
var paths: Array = []
var last_leader: Array[Vector3] = []
var camera := Camera3D.new()
var label := Label.new()
var old_layer := 0
var old_mask := 0
var notice := ""

func _ready() -> void:
	process_priority = -10
	rover = game.lorry
	actor = game.theia
	rover.controlled = true
	add_child(camera)
	camera.far = 50000
	camera.fov = 65
	var hud := CanvasLayer.new()
	add_child(hud)
	hud.add_child(label)
	label.position = Vector2(24, 220)
	label.add_theme_font_size_override("font_size", 20)
	_spawn_trucks.call_deferred()

func _spawn_trucks() -> void:
	while not rover.rig_ready:
		await get_tree().process_frame
	var stands := PackedVector3Array()
	var departure := rover.global_basis.z
	var city: Node = game.surface.get_node_or_null("TychoCity")
	if city != null:
		# TychoCity builds CityPaths/TychoCosmoport lazily from its own _process(),
		# not from _ready(), so it may not exist on the frame the rover becomes
		# ready. Give it a couple of seconds before falling back to a bare offset.
		var wait_frames := 0
		var port: Node = null
		while wait_frames < 240:
			port = city.get_node_or_null("CityPaths/TychoCosmoport")
			if port != null and port.has_method("truck_stands_global") and not port.truck_stands_global().is_empty():
				break
			port = null
			await get_tree().process_frame
			wait_frames += 1
		if port != null:
			stands = port.truck_stands_global()
			departure = port.truck_departure_global()
	for i in 2:
		var truck := Truck.new()
		truck.terrain = game.terrain
		truck.controlled = true
		var start := stands[i] if i < stands.size() else rover.global_position + rover.global_basis.z * (22.0 * (i + 1))
		# _route_point(0) reads route[route_index] (1 after set_patrol_route), so
		# the spawn point must be duplicated at index 0 and 1, not just index 0.
		truck.set_patrol_route(PackedVector3Array([start, start, start + departure * 24.0]))
		game.surface.add_child(truck)
		trucks.append(truck)
		paths.append([])
		last_leader.append(start)
		truck.set_light_mode(1)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# E is the common nearby interaction key: a bench uses it through
		# moonwalk.gd when no rover interaction claims the event.
		if event.physical_keycode == KEY_E and not actor.paused and not game.map_mode and (driving or actor.global_position.distance_to(rover.global_position) < 8):
			if driving:
				_exit_rover()
			elif actor.global_position.distance_to(rover.global_position) < 8 and not actor.sitting and not actor.climb_active:
				_enter_rover()
			get_viewport().set_input_as_handled()
		elif driving:
			if event.physical_keycode == KEY_ESCAPE:
				actor.set_paused(not actor.paused)
			elif event.physical_keycode == KEY_L:
				rover.set_light_mode(rover.light_mode + 1)
			# Walking, bench and orbital controls must not run inside the rover.
			get_viewport().set_input_as_handled()

func _enter_rover() -> void:
	if not rover.rig_ready or rover.linear_velocity.length() > 0.5:
		return
	driving = true
	actor.stop_autopilot()
	actor.enabled = false
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.hide()
	old_layer = actor.collision_layer
	old_mask = actor.collision_mask
	actor.collision_layer = 0
	actor.collision_mask = 0
	camera.global_position = rover.global_position + rover.global_basis.z * 12 + Vector3.UP * 6
	camera.make_current()
	notice = ""

func _exit_rover() -> void:
	if rover.linear_velocity.length() > 0.5:
		notice = "Zatrzymaj łazik przed wysiadaniem"
		return
	var space := rover.get_world_3d().direct_space_state
	for side in [-1.0, 1.0]:
		var p: Vector3 = rover.global_position + rover.global_basis.x * side * 4.5
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3, p - Vector3.UP * 6, 1, [rover.get_rid(), actor.get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or Vector3(hit.normal).y < 0.85:
			continue
		p = hit.position + Vector3.UP * 0.15
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.6
		capsule.height = 2.1
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = p + Vector3.UP * 1.1
		query.collision_mask = 1
		query.exclude = [actor.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			continue
		driving = false
		rover.drive_throttle = 0
		rover.drive_brake = true
		actor.global_position = p
		actor.velocity = Vector3.ZERO
		actor.collision_layer = old_layer
		actor.collision_mask = old_mask
		actor.enabled = true
		actor.show()
		actor.set_physics_process(true)
		actor.set_process(true)
		actor.camera.make_current()
		notice = ""
		return
	notice = "Brak bezpiecznego miejsca obok łazika"

func _physics_process(delta: float) -> void:
	if not is_instance_valid(rover):
		return
	var suspended: bool = actor.paused or game.map_mode or game.landing_busy
	for vehicle in [rover] + trucks:
		if vehicle.rig_ready:
			vehicle.freeze = suspended or not game.terrain.has_ground(vehicle.global_position)
	if driving:
		actor.global_position = rover.global_position
		game.terrain.update_focus(rover.global_position)
		rover.drive_throttle = 0.0 if suspended else float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		rover.drive_steer = 0.0 if suspended else float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D))
		rover.drive_brake = suspended or Input.is_physical_key_pressed(KEY_SPACE)
		var target := rover.global_position + Vector3.UP * 2.5
		var desired := target + rover.global_basis.z * 12 + Vector3.UP * 5
		var ray := PhysicsRayQueryParameters3D.create(target, desired, 1, [rover.get_rid()])
		var hit := rover.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			desired = hit.position + hit.normal * 0.4
		camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-delta * 6))
		camera.look_at(target)
	for i in trucks.size():
		_follow(i, suspended)
	# Keep the entire convoy inside the collision-streamed neighbourhood.
	if driving:
		if notice.begins_with("Konwój czeka"):
			notice = ""
		for truck in trucks:
			if truck.global_position.distance_to(rover.global_position) > 85:
				rover.drive_throttle = 0
				rover.drive_brake = true
				notice = "Konwój czeka na drona — sprawdź przejazd za łazikiem"
	label.text = ("LORRY  %.1f km/h\nW/S: napęd / wstecz • A/D: skręt • Spacja: hamulec\nE: wysiądź • L: światła • Esc: pauza\nDrony transportowe: %d\n%s" % [rover.linear_velocity.length() * 3.6, trucks.size(), notice]) if driving else ("E: wsiądź do Lorry" if actor.global_position.distance_to(rover.global_position) < 8 else "")

func _follow(i: int, suspended: bool) -> void:
	var truck := trucks[i]
	var leader: VehicleBody3D = rover if i == 0 else trucks[i - 1]
	var path: Array = paths[i]
	if path.size() < 2048 and leader.global_position.distance_to(last_leader[i]) > 2:
		path.append(leader.global_position)
		last_leader[i] = leader.global_position
	if path.size() >= 2048:
		# Do not erase an untraversed bend and cut through the terrain.
		leader.drive_brake = true
	while not path.is_empty() and truck.global_position.distance_to(path[0]) < 3:
		path.pop_front()
	truck.drive_throttle = 0
	truck.drive_brake = true
	if suspended or path.is_empty() or not truck.rig_ready:
		return
	var speed := truck.linear_velocity.length()
	var gap := truck.global_position.distance_to(leader.global_position)
	var safe_gap := 24.0 + speed * 1.5 + speed * speed / (2 * 0.8 * 1.62)
	if gap < safe_gap or leader.linear_velocity.dot(-leader.global_basis.z) < -0.2:
		return
	var target: Vector3 = path[0]
	var direction := target - truck.global_position
	direction.y = 0
	var angle := (-truck.global_basis.z).signed_angle_to(direction.normalized(), Vector3.UP)
	truck.drive_steer = clampf(angle * 2, -1, 1)
	# Stop for obstacles instead of pushing them or shortcutting a bend.
	var start := truck.global_position + Vector3.UP * 1.8
	var ray := PhysicsRayQueryParameters3D.create(start, start - truck.global_basis.z * (5 + speed * 2), 1, [truck.get_rid()])
	if not truck.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return
	truck.drive_brake = speed > (3.0 if absf(angle) > 0.4 else 7.0)
	truck.drive_throttle = 0.7 if not truck.drive_brake else 0.0
