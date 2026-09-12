extends "res://scripts/theia.gd"

signal pause_changed(value: bool)
signal camera_changed(index: int)
signal controls_changed()
signal autopilot_changed()

const CAMERA_MODES := [
	{"name": "frog", "label": "Żabia", "distance": 2.8, "pitch_deg": 9.0, "target_height": 1.0, "fov": 60.0},
	{"name": "normal", "label": "Normalna", "distance": 5.2, "pitch_deg": 14.0, "target_height": 1.4, "fov": 48.0},
	{"name": "bird", "label": "Z lotu ptaka", "distance": 8.4, "pitch_deg": 58.0, "target_height": 1.85, "fov": 42.0},
	{"name": "fpv", "label": "Pierwsza osoba", "eye_height": 1.75, "forward_offset": 0.08, "fov": 72.0},
	{"name": "free", "label": "Swobodna", "fov": 72.0},
]
var target_height := 1.4
var fpv_pitch := 0.0
var free_yaw := 0.0
var free_pitch := 0.0
var free_position := Vector3.ZERO
var mouse_sensitivity := 0.006
var paused := false
var turn_direction := 0
var turn_elapsed := 0.0
var turn_duration := 0.0
var turn_repeat_elapsed := 0.0
var active_visual := 0
var classic_controls := true
var persist_settings := true
var autopilot := false
var autopilot_direction := Vector3.FORWARD
var autopilot_running := false
var blocked_time := 0.0
var previous_camera := 1
var orbit_length := -1.0

func toggle_autopilot() -> void:
	autopilot = not autopilot
	blocked_time = 0
	turn_direction = 0
	if autopilot:
		autopilot_direction = Vector3(velocity.x, 0, velocity.z)
		if autopilot_direction.length() < 0.1:
			autopilot_direction = Vector3(sin(visual_yaw), 0, cos(visual_yaw))
		autopilot_direction = autopilot_direction.normalized()
		autopilot_running = Input.is_action_pressed("sprint" if classic_controls else "run_forward")
	autopilot_changed.emit()

func stop_autopilot() -> void:
	if autopilot:
		autopilot = false
		velocity.x = 0
		velocity.z = 0
		autopilot_changed.emit()

func toggle_free_camera() -> void:
	if mode == 4:
		set_camera_mode(previous_camera)
	else:
		previous_camera = mode
		set_camera_mode(4)

func _save_settings() -> void:
	if not persist_settings: return
	var config := ConfigFile.new()
	config.set_value("controls", "classic", classic_controls)
	config.set_value("controls", "sensitivity", mouse_sensitivity)
	config.set_value("controls", "camera", mode)
	config.save("user://controls.cfg")

func set_control_scheme(classic: bool) -> void:
	stop_autopilot()
	classic_controls = classic
	turn_direction = 0
	turn_repeat_elapsed = 0
	velocity = Vector3.ZERO
	set_camera_mode(1 if classic else 3)
	_save_settings()
	controls_changed.emit()

func set_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.001, 0.012)
	_save_settings()

func _ready() -> void:
	super._ready()
	if not InputMap.has_action("run_forward"): InputMap.add_action("run_forward")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	if not InputMap.action_has_event("run_forward", key): InputMap.action_add_event("run_forward", key)
	for pair in [["sprint", KEY_SHIFT], ["fly_up", KEY_SPACE], ["fly_down", KEY_CTRL]]:
		if not InputMap.has_action(pair[0]): InputMap.add_action(pair[0])
		var binding := InputEventKey.new()
		binding.physical_keycode = pair[1]
		if not InputMap.action_has_event(pair[0], binding): InputMap.action_add_event(pair[0], binding)
	pivot.rotation.y = visual_yaw
	persist_settings = not ("--smoke-test" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args() or "--capture-sky" in OS.get_cmdline_user_args() or "--camera-test" in OS.get_cmdline_user_args())
	var config := ConfigFile.new()
	var initial_camera := 1
	if persist_settings and config.load("user://controls.cfg") == OK:
		classic_controls = config.get_value("controls", "classic", true)
		mouse_sensitivity = clampf(config.get_value("controls", "sensitivity", 0.006), 0.001, 0.012)
		initial_camera = config.get_value("controls", "camera", 1 if classic_controls else 3)
	set_camera_mode(initial_camera)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_paused(value: bool) -> void:
	paused = value
	for player in players:
		player.speed_scale = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	pause_changed.emit(paused)

func cycle_camera() -> void:
	if classic_controls:
		set_camera_mode(1 if mode == 3 else 3)
	else:
		set_camera_mode((mode + 1) % CAMERA_MODES.size())

func set_camera_mode(index: int) -> void:
	orbit_length = -1.0
	if classic_controls:
		if index == 3 and mode != 3:
			var look := -camera.global_basis.z
			visual_yaw = atan2(look.x, look.z)
		elif index < 3 and mode >= 3:
			var look := -camera.global_basis.z
			yaw = atan2(look.x, look.z) - PI
	mode = clampi(index, 0, CAMERA_MODES.size() - 1)
	var preset: Dictionary = CAMERA_MODES[mode]
	if mode == 4:
		free_position = camera.global_position
		free_yaw = visual_yaw
		free_pitch = 0
		if not autopilot:
			velocity.x = 0
			velocity.z = 0
	elif mode < 3:
		distance = preset.distance
		pitch = deg_to_rad(preset.pitch_deg)
		target_height = preset.target_height * (reference_height_m / REFERENCE_HEIGHT_M)
		if mode == 1 and not classic_controls: yaw = 0
	else:
		if not classic_controls: yaw = visual_yaw
	camera.fov = preset.fov
	camera.near = 0.02 if mode == 3 else 0.05
	pivot.visible = mode != 3
	_update_camera()
	camera_changed.emit(mode)
	_save_settings()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled: return
	if (not classic_controls and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE):
		set_paused(not paused)
		get_viewport().set_input_as_handled()
		return
	if paused: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if mode == 3:
			visual_yaw = fposmod(visual_yaw - event.relative.x * mouse_sensitivity, TAU)
			fpv_pitch = clampf(fpv_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-70), deg_to_rad(82))
		elif mode == 4:
			free_yaw = fposmod(free_yaw - event.relative.x * mouse_sensitivity, TAU)
			free_pitch = clampf(free_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-70), deg_to_rad(82))
		else:
			yaw = fposmod(yaw - event.relative.x * mouse_sensitivity, TAU)
			if classic_controls:
				pitch = clampf(pitch + event.relative.y * mouse_sensitivity, deg_to_rad(-15), deg_to_rad(80))
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not classic_controls: cycle_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(2.2, distance - 0.7)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(12, distance + 0.7)
	if event is InputEventKey and event.pressed and not event.echo:
		if mode != 4 and event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
			stop_autopilot()
		match event.physical_keycode:
			KEY_P, KEY_NUMLOCK: toggle_autopilot()
			KEY_V: toggle_free_camera()
			KEY_A:
				if mode != 4 and not classic_controls: _start_turn(-1)
			KEY_D:
				if mode != 4 and not classic_controls: _start_turn(1)
			KEY_C: cycle_camera()
			KEY_K: cycle_outline_style()
			KEY_B: cycle_painterly_style()
			KEY_R, KEY_F8:
				if (classic_controls and event.physical_keycode == KEY_F8) or (not classic_controls and event.physical_keycode == KEY_R):
					stop_autopilot()
					position = Vector3(spawn_position.x, terrain.height_at(spawn_position.x, spawn_position.z) + 0.2, spawn_position.z)
					velocity = Vector3.ZERO
			KEY_SPACE:
				_try_jump()

func _try_jump() -> void:
	if is_on_floor() and mode != 4: velocity.y = 2.6

func _start_turn(direction: int) -> void:
	if turn_direction != 0: return
	turn_direction = direction
	turn_elapsed = 0
	turn_repeat_elapsed = 0
	active_visual = 2 if direction < 0 else 3
	turn_duration = players[active_visual].get_animation(players[active_visual].current_animation).length / 6.0
	players[active_visual].seek(0, true)

func _physics_process(delta: float) -> void:
	if not enabled or paused: return
	if classic_controls:
		_physics_classic(delta)
		return
	terrain.update_focus(position)
	var running := Input.is_action_pressed("run_forward")
	var axis := 1.0 if running else Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var turn_axis := int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))
	if mode == 4:
		var flat := Vector3(sin(free_yaw), 0, cos(free_yaw))
		var look := flat * cos(free_pitch) + Vector3.UP * sin(free_pitch)
		var right := Vector3(cos(free_yaw), 0, -sin(free_yaw))
		free_position += (look * axis + right * turn_axis) * 8.0 * (4.0 if running else 1.0) * delta
		if autopilot:
			_move_classic_body(delta, autopilot_direction, autopilot_running)
		elif not is_on_floor() or velocity.y > 0:
			_move_classic_body(delta, Vector3.ZERO, false)
		else:
			_sync_visual(false, false)
		_update_camera()
		return
	if autopilot:
		_move_classic_body(delta, autopilot_direction, autopilot_running)
		return
	if turn_axis != 0:
		turn_repeat_elapsed += delta
		if turn_repeat_elapsed >= 0.1 and turn_direction == 0: _start_turn(turn_axis)
	else:
		turn_repeat_elapsed = 0
	if turn_direction != 0:
		turn_elapsed += delta
		players[active_visual].seek(minf(turn_elapsed, turn_duration), true)
		if turn_elapsed >= turn_duration:
			visual_yaw -= deg_to_rad(20.0 * turn_direction)
			turn_direction = 0
		axis = 0
	var direction := Vector3(sin(visual_yaw), 0, cos(visual_yaw))
	var speed := 5.2 if running else 2.6
	velocity.x = direction.x * axis * speed
	velocity.z = direction.z * axis * speed
	if not terrain.has_ground(position + velocity * delta):
		velocity.x = 0
		velocity.z = 0
	velocity.y -= 1.62 * delta
	var before := position
	move_and_slide()
	total_distance += Vector2(position.x - before.x, position.z - before.z).length()
	pivot.rotation.y = visual_yaw
	_sync_visual(axis != 0, running)
	if is_on_floor() and position.distance_to(last_foot) > 0.62:
		_stamp_foot()
		last_foot = position
	if position.y < terrain.height_at(position.x, position.z) - 15:
		position.y = terrain.height_at(position.x, position.z) + 0.2
		velocity = Vector3.ZERO
	_update_camera()

func _classic_direction(axis: Vector2) -> Vector3:
	# Ground movement follows the horizontal camera bearing, even when looking up/down.
	var forward := -camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := camera.global_basis.x
	right.y = 0
	return (right.normalized() * axis.x - forward * axis.y).limit_length()

func _physics_classic(delta: float) -> void:
	terrain.update_focus(position)
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var running := Input.is_action_pressed("sprint") and not axis.is_zero_approx()
	if mode == 4:
		var vertical := Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down")
		var direction := (camera.global_basis.x * axis.x + camera.global_basis.z * axis.y + Vector3.UP * vertical).limit_length()
		free_position += direction * (32.0 if Input.is_action_pressed("sprint") else 8.0) * delta
		if autopilot:
			_move_classic_body(delta, autopilot_direction, autopilot_running)
		elif not is_on_floor() or velocity.y > 0:
			_move_classic_body(delta, Vector3.ZERO, false)
		else:
			_sync_visual(false, false)
		_update_camera()
		return
	var direction := _classic_direction(axis)
	if autopilot:
		direction = autopilot_direction
		running = autopilot_running
	_move_classic_body(delta, direction, running)

func _move_classic_body(delta: float, direction: Vector3, running: bool) -> void:
	var speed := 5.2 if running else 2.6
	# Responsive acceleration and braking, identical speed on diagonals.
	velocity.x = move_toward(velocity.x, direction.x * speed, 18.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 18.0 * delta)
	if not terrain.has_ground(position + velocity * delta):
		velocity.x = 0
		velocity.z = 0
	velocity.y -= 1.62 * delta
	var before := position
	move_and_slide()
	total_distance += Vector2(position.x - before.x, position.z - before.z).length()
	if autopilot:
		blocked_time = blocked_time + delta if Vector2(position.x - before.x, position.z - before.z).length() < 0.05 * delta else 0.0
		if blocked_time > 1.0: stop_autopilot()
	if mode != 3 and not direction.is_zero_approx():
		visual_yaw = lerp_angle(visual_yaw, atan2(direction.x, direction.z), 1.0 - exp(-14.0 * delta))
	pivot.rotation.y = visual_yaw
	_sync_visual(not direction.is_zero_approx(), running)
	if is_on_floor() and position.distance_to(last_foot) > 0.62:
		_stamp_foot()
		last_foot = position
	if position.y < terrain.height_at(position.x, position.z) - 15:
		position.y = terrain.height_at(position.x, position.z) + 0.2
		velocity = Vector3.ZERO
	_update_camera()

func _sync_visual(moving: bool, running: bool) -> void:
	if turn_direction == 0 or mode == 4: active_visual = int(running and moving)
	for i in visuals.size():
		visuals[i].visible = i == active_visual
		players[i].speed_scale = (0.8 if i == 0 else 0.75) if i == active_visual and i < 2 and moving and is_on_floor() else 0
	pivot.visible = mode != 3

func _update_camera() -> void:
	if mode == 4:
		camera.global_position = free_position
		var look := Vector3(sin(free_yaw), 0, cos(free_yaw)) * cos(free_pitch) + Vector3.UP * sin(free_pitch)
		camera.look_at(free_position + look)
	elif mode == 3:
		var flat := Vector3(sin(visual_yaw), 0, cos(visual_yaw))
		var eye: Vector3 = global_position + Vector3.UP * eye_height_m
		camera.global_position = eye + flat * CAMERA_MODES[3].forward_offset
		camera.look_at(eye + flat * cos(fpv_pitch) + Vector3.UP * sin(fpv_pitch))
	else:
		var target := global_position + Vector3.UP * target_height
		var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
		var wanted := target + offset
		var query := PhysicsRayQueryParameters3D.create(target, wanted)
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		# Retract along the orbit arm, never sideways along a triangle's normal.
		# Return gently after an obstruction instead of snapping to full distance.
		var allowed := distance
		if not hit.is_empty(): allowed = maxf(0.1, target.distance_to(hit.position) - 0.25)
		if orbit_length < 0.0 or allowed < orbit_length:
			orbit_length = allowed
		wanted = target + offset.normalized() * minf(orbit_length, allowed)
		camera.global_position = wanted
		camera.look_at(target)

func _process(delta: float) -> void:
	# theia.gd (the base class) has no _process right now, so this is a no-op
	# up the chain -- kept anyway, since a derived _process silently replaces
	# the base one instead of extending it in GDScript, and that already
	# caused one base _process to sit dead for a whole debugging session.
	super._process(delta)
	# Keep the painterly post scoped to this camera even while map mode disables us.
	if painterly_layer != null:
		painterly_layer.visible = painterly_style != 0 and camera.current
	if not enabled or paused: return
	if mode < 3 and orbit_length >= 0:
		orbit_length = move_toward(orbit_length, distance, 3.0 * delta)
	_update_camera()
