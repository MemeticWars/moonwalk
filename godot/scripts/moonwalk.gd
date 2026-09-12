extends Node3D

const ColonyUtil = preload("res://scripts/colony_util.gd")
const Terrain = preload("res://scripts/lunar_terrain.gd")
const Theia = preload("res://scripts/human_controller.gd")
const Agnes = preload("res://scripts/agnes.gd")
const Globe = preload("res://scripts/moon_globe.gd")
const Approach = preload("res://scripts/lunar_approach.gd")
const Lorry = preload("res://scripts/lunar_lorry.gd")
const RoadStreamer = preload("res://scripts/road_streamer.gd")
const LunarHorizon = preload("res://scripts/lunar_horizon.gd")
const TYCHO_PLAYER_START := Vector3(-26.0, 0.0, -67.0)
const LUBIN_DEEP_PLAYER_START := Vector3(-5.0, 0.0, -10.0)
const TYCHO_GATE_DIR := Vector2(0.0, -1.0)
const TYCHO_HIGHWAY_ORIGIN := Vector2(-9.0, -14.0)
const TYCHO_HIGHWAY_DIR := Vector2(0.2239, -0.9746)
var terrain: Node3D
var theia: CharacterBody3D
var globe: Node3D
var lorry: Node3D
var roads: Node3D
var surface := Node3D.new()
var colonies_data: Dictionary = {}
var active_colony_name := "Silesia"
var active_colony: Dictionary = {}
var status: Label
var style_status: Label
var title: Label
var subtitle: Label
var hint: Label
var map_mode := false
var landing_busy := false
var coverage := false
var debug_label: Label
var panel: PanelContainer
var pause_panel: PanelContainer
var camera_picker: OptionButton
var camera_info: Label
var controls_hint: Label
var controls_picker: OptionButton
var controls_note: Label
var autopilot_button: Button
var lunar_sky: Node
var planet_sun_direction := Vector3.ZERO
var sky_phase_slider: HSlider
# Godot's MovieWriter can only be armed at engine start (--write-movie) and is
# finalised on a clean quit. So "start recording" relaunches the game into a
# second process that is the movie writer; "stop" quits that process.
var recording := "--recording" in OS.get_cmdline_user_args()
var rec_button: Button
var rec_indicator: Label
var location_panel: PanelContainer
var location_picker: OptionButton
var custom_lat: SpinBox
var custom_lon: SpinBox
var custom_row: HBoxContainer
var location_goto_button: Button

func _ready() -> void:
	_setup_light()
	colonies_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/colonies.json"))
	var requested := "Tycho Station"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--colony="):
			requested = arg.substr("--colony=".length())
	add_child(surface)
	_build_surface(requested)
	_apply_recording_spawn()
	_build_ui()
	theia.pause_changed.connect(_pause_changed)
	theia.camera_changed.connect(_camera_changed)
	theia.controls_changed.connect(_controls_changed)
	theia.autopilot_changed.connect(_autopilot_changed)
	if "--smoke-test" in OS.get_cmdline_user_args():
		_smoke_test.call_deferred()
	if "--climb-test" in OS.get_cmdline_user_args():
		_climb_test.call_deferred()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()
	if "--capture-sky" in OS.get_cmdline_user_args():
		_capture_sky.call_deferred()
	if "--lorry-test" in OS.get_cmdline_user_args():
		_lorry_test.call_deferred()
	if "--capture-lorry" in OS.get_cmdline_user_args():
		_capture_lorry.call_deferred()
	if "--road-test" in OS.get_cmdline_user_args():
		_road_test.call_deferred()
	if "--dem-probe" in OS.get_cmdline_user_args():
		_dem_probe.call_deferred()
	if "--capture-road" in OS.get_cmdline_user_args():
		_capture_road.call_deferred()
	if "--capture-globe" in OS.get_cmdline_user_args():
		_capture_globe.call_deferred()
	if "--capture-fox" in OS.get_cmdline_user_args():
		_capture_fox.call_deferred()
	if "--capture-fox-wander" in OS.get_cmdline_user_args():
		_capture_fox_wander.call_deferred()
	if "--capture-rain-outline" in OS.get_cmdline_user_args():
		_capture_rain_outline.call_deferred()
	if "--capture-run-jump" in OS.get_cmdline_user_args():
		_capture_run_jump.call_deferred()
	if "--capture-city" in OS.get_cmdline_user_args():
		_capture_city.call_deferred()

func _capture_city() -> void:
	theia.set_physics_process(false)
	var city := surface.get_node("TychoCity")
	var deadline := Time.get_ticks_msec() + 90000
	while city.loaded.size() < city.descriptors.size() or not terrain.queue.is_empty():
		if Time.get_ticks_msec() > deadline:
			push_error("City capture timed out waiting for streaming")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var camera := Camera3D.new()
	surface.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 245.0
	camera.far = 250000.0
	camera.position = Vector3(145, terrain.city_level + 140, -195)
	camera.look_at(Vector3(0, terrain.city_level, 25))
	camera.make_current()
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/tycho_city_overview.png")
	get_viewport().get_texture().get_image().save_png("res://../artifacts/tycho_city_lamps.png")
	city.ground_details.get_node("TychoDome").hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/tycho_city_layout.png")
	print("TYCHO CITY CAPTURE: ", city.loaded.size(), " modules")
	get_tree().quit()

func _climb_test() -> void:
	assert(theia.has_method("_try_start_climb"), "Climb test requires a human controller")
	var city := surface.get_node("TychoCity")
	var target := -1
	for i in city.descriptors.size():
		if city.descriptors[i].kind == "twin-houses":
			target = i
			break
	assert(target >= 0, "Tycho needs a twin-houses to test its facade")
	var root: Node3D = city.loaded.get(target)
	var deadline := Time.get_ticks_msec() + 60000
	while root == null and Time.get_ticks_msec() < deadline:
		terrain.update_focus(Vector3(0, terrain.city_level, 60))
		await get_tree().process_frame
		root = city.loaded.get(target)
	assert(root != null and root.has_node("ClimbSurface"), "Detailed facade collision must stream for twin-houses")
	# Scan just outside the real asset until a layer-2 facade triangle is found.
	# This deliberately calls the same function as a Q press, not a private
	# substitute, so the test proves that the playable interaction can start.
	var found := false
	for radius in [8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0]:
		if found: break
		for step in 24:
			var angle := TAU * float(step) / 24.0
			theia.position = root.global_position + Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)
			# terrain.height_at() is the natural heightmap; the plaza floor around
			# city buildings is flattened to terrain.city_level and can sit well
			# above or below that heightmap value at the same (x, z). Using the
			# wrong one here spawns Agnes floating above (or embedded below) the
			# real floor, and the very first move_and_slide of the climb resolves
			# the gap as a multi-metre snap that looked exactly like "climbs for
			# a moment, then falls".
			theia.position.y = terrain.city_level + 0.15
			theia.visual_yaw = angle + PI
			if not theia._nearest_climb_surface().is_zero_approx():
				found = true
				break
	assert(found, "Q must find a real twin-houses facade within its interaction range")
	# A "found" spot from the sweep above can still land inside the COARSE
	# box collider (layer 1, what actually stops movement) -- the detailed
	# facade trimesh (layer 2, climb-ray only) sits inside it, and for some
	# building assets (central-house, ~50x51 m -- almost certainly an import-
	# scale bug, well outside every other building's 18-24 m range) the box
	# extends metres beyond the facade. Handing that overlap to climb's own
	# move_and_slide depenetrated her straight down through the box's floor
	# -- not a fall, and nothing to do with the facade's own detail. Back
	# away in small steps until she's clear of solid geometry while the
	# facade is still within Q's own interaction reach, the way a player who
	# stopped at a comfortable distance from the wall would be.
	var direction: Vector3 = theia._nearest_climb_surface()
	assert(not direction.is_zero_approx(), "Facade direction must still resolve at the found spot")
	# No "+ PI" here: direction already points FROM Agnes TOWARD the wall
	# (see _nearest_climb_surface), the same convention _try_start_climb
	# itself uses for visual_yaw. The scan loop's "angle + PI" above is a
	# different thing -- angle is the sweep's OUTWARD radial direction from
	# the building, so facing back in needs the flip; this doesn't.
	theia.visual_yaw = atan2(direction.x, direction.z)
	var capsule := CapsuleShape3D.new()
	capsule.radius = theia.collision_radius_m
	capsule.height = theia.reference_height_m
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.collision_mask = 1
	shape_query.exclude = [theia.get_rid()]
	var clear := false
	for _step in 400:
		shape_query.transform = Transform3D(Basis(), theia.position + Vector3.UP * theia.reference_height_m * 0.5)
		if theia.get_world_3d().direct_space_state.intersect_shape(shape_query, 1).is_empty():
			clear = true
			break
		theia.position -= direction * 0.05
		theia.position.y = terrain.city_level + 0.15
	assert(clear, "Must find a spot clear of the coarse movement box near the found facade")
	assert(not theia._nearest_climb_surface().is_zero_approx(), "Facade must still be reachable from the clear spot")
	var start_y := theia.position.y
	assert(theia._try_start_climb(), "Q climb interaction must enter the climbing animation")
	assert(theia.climb_active or theia.climb_approaching, "Climbing (or the walk-in approach) must become active")
	# A plinth or an oversized coarse box can hold the interaction range
	# without putting her close enough to climb yet -- she walks in first.
	# Give that a few seconds before expecting the climb pose itself.
	var approach_deadline_ms := Time.get_ticks_msec() + 5000
	while theia.climb_approaching and Time.get_ticks_msec() < approach_deadline_ms:
		await get_tree().process_frame
	assert(theia.climb_active and theia.active_visual == 6, "Climbing animation must become visible after the approach")
	await get_tree().create_timer(0.6).timeout
	assert(theia.position.y > start_y + 0.15, "Agnes must physically climb the facade")
	print("CLIMB TEST PASS (short): real facade found and Agnes climbed %.2f m" % (theia.position.y - start_y))
	# Regression check: a real player holds Q and expects to keep climbing all
	# the way to the roof, not stop partway up. Keep climbing (or finishing
	# onto the roof) for several seconds and fail loudly on any premature
	# cancel or fall.
	var highest_y := theia.position.y
	var deadline_ms := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
		if theia.position.y > highest_y:
			highest_y = theia.position.y
		# is_on_floor() can lag a tick behind climb_finishing actually ending
		# (its landing is a scripted position-match, not a pure gravity
		# touchdown) -- also accept "hasn't actually lost height" as proof
		# she isn't free-falling, so that one-tick handoff isn't a false trip.
		assert(theia.climb_active or theia.climb_finishing or theia.climb_auto_walk or theia.stand_up_active or theia.is_on_floor() or theia.position.y >= highest_y - 0.05, "Agnes must not free-fall off the facade mid-climb (dropped from %.2f m to %.2f m)" % [highest_y, theia.position.y])
		assert(theia.position.y > highest_y - 0.35, "Agnes fell %.2f m from her highest point mid-climb" % (highest_y - theia.position.y))
		if not theia.climb_active and not theia.climb_finishing and not theia.climb_auto_walk and not theia.stand_up_active:
			break
	assert(not theia.climb_active and not theia.climb_finishing and not theia.climb_auto_walk and not theia.stand_up_active, "Climb must reach the roof and finish within 60 s")
	var landing_y := theia.position.y
	await get_tree().create_timer(2.0).timeout
	assert(theia.is_on_floor() and theia.position.y > landing_y - 0.15, "Roof must support Agnes after the climb ends")

	print("CLIMB TEST PASS (full): reached the roof at %.2f m (climbed %.2f m total)" % [theia.position.y, theia.position.y - start_y])
	get_tree().quit()

func _build_surface(colony_name: String, destination: Dictionary = {}) -> void:
	active_colony_name = colony_name
	active_colony = destination if not destination.is_empty() else ColonyUtil.find(colonies_data.locations, colony_name)
	terrain = Terrain.new()
	terrain.colony = active_colony
	surface.add_child(terrain)
	var horizon := LunarHorizon.new()
	horizon.terrain = terrain
	surface.add_child(horizon)
	roads = RoadStreamer.new()
	roads.terrain = terrain
	roads.active_colony = colony_name
	surface.add_child(roads)
	if not active_colony.get("wilderness", false):
		_build_outpost()
	if colony_name == "Tycho Station":
		var city := preload("res://scripts/tycho_city.gd").new()
		city.terrain = terrain
		surface.add_child(city)
	lorry = null
	if not active_colony.get("wilderness", false):
		lorry = Lorry.new()
		lorry.terrain = terrain
		if colony_name == "Tycho Station":
			lorry.set_patrol_route(_tycho_lorry_patrol())
		surface.add_child(lorry)
	if not is_instance_valid(theia):
		theia = Agnes.new()
	theia.terrain = terrain
	theia.spawn_position = _player_start()
	surface.add_child(theia)

func _tycho_lorry_patrol() -> PackedVector3Array:
	# The rover waits just inside the southern airlock. It repeatedly approaches
	# the gateway, backs into the habitat, then makes a second approach that can
	# carry it out through the open portal and onto the real highway centreline.
	var centre := Vector2(0.0, 25.0)
	var gate := TYCHO_GATE_DIR.normalized()
	var highway := TYCHO_HIGHWAY_DIR.normalized()
	return PackedVector3Array([
		_tycho_gate_point(centre, gate, 88.0),  # parked on the inner side of the airlock
		_tycho_gate_point(centre, gate, 97.0),  # inspect the threshold
		_tycho_gate_point(centre, gate, 88.0),  # return safely inside the dome
		_tycho_gate_point(centre, gate, 97.0),
		_tycho_gate_point(centre, gate, 110.0), # successful crossing: just outside the airlock
		_tycho_highway_point(highway, 140.0),
		_tycho_highway_point(highway, 190.0), # continue along the elevated highway
		_tycho_highway_point(highway, 140.0),
		_tycho_gate_point(centre, gate, 110.0),
		_tycho_gate_point(centre, gate, 97.0),
	])

func _tycho_gate_point(centre: Vector2, gate: Vector2, radius_m: float) -> Vector3:
	var p := centre + gate * radius_m
	return Vector3(p.x, 0.0, p.y)

func _tycho_highway_point(highway: Vector2, station_m: float) -> Vector3:
	var p := TYCHO_HIGHWAY_ORIGIN + highway * station_m
	return Vector3(p.x, 0.0, p.y)

func _player_start() -> Vector3:
	# Default facing is +z. Tycho begins beside the station, on the InPost highway
	# approach along the real great-circle bearing; Lubin Deep begins on the
	# interchange-access path north of the outpost, facing the highway approach.
	match active_colony_name:
		"Tycho Station":
			return TYCHO_PLAYER_START
		"Lubin Deep":
			return LUBIN_DEEP_PLAYER_START
		_:
			return Vector3.ZERO

## A recording relaunch carries the live player pose so the film starts where the
## player pressed the button, not back at the colony entrance.
func _apply_recording_spawn() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--rec-at="):
			continue
		var p := arg.substr("--rec-at=".length()).split(",")
		if p.size() >= 3:
			var start := Vector3(float(p[0]), float(p[1]), float(p[2]))
			theia.spawn_position = start
			theia.position = start
		if p.size() >= 4:
			theia.visual_yaw = float(p[3])
			theia.pivot.rotation.y = theia.visual_yaw

## Record button / key I. In a normal session this spawns the movie-writer
## process and quits; in the movie-writer process it quits, finalising the file.
func _toggle_recording() -> void:
	if recording:
		get_tree().quit()
		return
	if theia.paused:
		theia.set_paused(false)
	if map_mode:
		_toggle_map()
	var out_dir := ProjectSettings.globalize_path("res://../artifacts")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stamp := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var out_path := "%s/moonwalk_%s.avi" % [out_dir, stamp]
	var pos := theia.position
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		# Running under the editor binary: point it at the project so it plays
		# the game instead of opening the project manager.
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array([
		"--write-movie", out_path,
		"--fixed-fps", "60",
		"--", "--colony=" + active_colony_name, "--recording",
		"--rec-at=%f,%f,%f,%f" % [pos.x, pos.y, pos.z, theia.visual_yaw],
	])
	if OS.create_instance(args) <= 0:
		push_error("Nie udało się uruchomić procesu nagrywania")
		if rec_button != null:
			rec_button.text = "Nagrywanie niedostępne"
		return
	get_tree().quit()

func _update_rec_button() -> void:
	if rec_button == null:
		return
	rec_button.text = "■  Zakończ nagrywanie (I)" if recording else "●  Nagrywaj (klawisz I)"
	rec_button.tooltip_text = "Nagrywanie uruchamia tryb Movie Maker Godota w osobnym oknie:\ngra działa wtedy w zwolnionym tempie, a gotowy plik .avi\ntrafia do folderu artifacts/. Klawisz I kończy film."

func _region_label(colony: Dictionary) -> String:
	# Silesia keeps its authored Polish copy; other colonies fall back to the
	# plain region field from colonies.json until someone writes local copy.
	if colony.get("name") == "Silesia":
		return "Wyżyny południowe"
	return colony.get("region", "")

func _format_latlon(colony: Dictionary) -> String:
	var lat: float = colony.get("latitude", 0.0)
	var lon: float = colony.get("longitude", 0.0)
	var lat_letter := "S" if lat < 0 else "N"
	var lon_letter := "E" if lon >= 0 else "W"
	return "%.2f° %s   /   %.2f° %s" % [absf(lat), lat_letter, absf(lon), lon_letter]

func _setup_light() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.002, 0.003, 0.006)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.66, 0.78)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Keep the Moon vacuum-black outside Tycho; the sealed habitat supplies its
	# own shallow FogVolume, so volumetric fog is only evaluated inside that air.
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.00001
	e.volumetric_fog_length = 96.0
	e.volumetric_fog_detail_spread = 1.4
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18, -42, 0)
	sun.light_color = Color(1, 0.96, 0.88)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50000.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Concentrate the first cascade around the player; progressively coarser
	# maps cover the kilometre-scale shadows of the surrounding mountains.
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.0032
	sun.directional_shadow_split_2 = 0.02
	sun.directional_shadow_split_3 = 0.16
	sun.directional_shadow_fade_start = 0.9
	sun.directional_shadow_pancake_size = 0.0
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	lunar_sky = preload("res://scripts/lunar_sky.gd").new()
	add_child(lunar_sky)
	lunar_sky.initialize(e, sun)

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	node.material_override = mat
	parent.add_child(node)
	node.position = pos
	return node

func _build_outpost() -> void:
	# The InPost point remains a small service kiosk beside the city access.
	var base := Node3D.new()
	surface.add_child(base)
	base.position = Vector3(-10, terrain.height_at(-10, -14), -14)
	_box(base, Vector3(3.4, 0.22, 2), Vector3(0, 0.15, 0), Color("353943")).create_trimesh_collision()
	_box(base, Vector3(2.8, 2.25, 0.8), Vector3(0, 1.36, 0), Color("c99b43")).create_trimesh_collision()
	for x in 4:
		for y in 3:
			_box(base, Vector3(0.61, 0.58, 0.035), Vector3(-1.03 + x * 0.69, 0.65 + y * 0.69, 0.425), Color("343637"))
	var sign := Label3D.new()
	sign.text = "INPOST  /  %s\nPUNKT TERENOWY 04" % active_colony_name.to_upper()
	sign.font_size = 48
	sign.pixel_size = 0.007
	sign.position = Vector3(0, 3.15, 0)
	sign.modulate = Color("f3c875")
	base.add_child(sign)
	_box(base, Vector3(0.12, 7, 0.12), Vector3(2, 3.5, 0), Color("9a9b99"))
	var beacon := OmniLight3D.new()
	beacon.light_color = Color("ffbb55")
	beacon.light_energy = 2
	beacon.omni_range = 9
	beacon.position = Vector3(2, 6.9, 0)
	base.add_child(beacon)
	for i in 10:
		var x := 3.4
		var z := -14.0 - i * 11
		_box(surface, Vector3(0.1, 0.85, 0.1), Vector3(x, terrain.height_at(x, z) + 0.42, z), Color("d1ac65"))

func _label(text: String, size: int, color: Color = Color("eef1f1")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	var bar := ColorRect.new()
	bar.color = Color(0.025, 0.036, 0.046, 0.92)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 100
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var brand := _label("M O O N W A L K", 25)
	brand.position = Vector2(32, 20)
	root.add_child(brand)
	var tag := _label("LUNAR INPOST   /   SURFACE EXPLORER", 12, Color("91a4af"))
	tag.position = Vector2(33, 58)
	root.add_child(tag)
	var buttons := HBoxContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	buttons.position = Vector2(-443, 27)
	buttons.add_theme_constant_override("separation", 10)
	root.add_child(buttons)
	for entry in [["O  /  Orbita", _toggle_map], ["Tab  /  Pokrycie", _toggle_coverage], ["C  /  Kamera", _cycle_camera]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(128, 42)
		button.pressed.connect(entry[1])
		buttons.add_child(button)
	panel = PanelContainer.new()
	panel.position = Vector2(32, 131)
	panel.custom_minimum_size = Vector2(310, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.036, 0.046, 0.84)
	style.border_color = Color("bfa36c")
	style.border_width_left = 2
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 17
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	box.add_child(_label("01   /   REKONESANS", 12, Color("d9b775")))
	title = _label(active_colony_name, 34)
	box.add_child(title)
	subtitle = _label(_region_label(active_colony) + "\n" + _format_latlon(active_colony), 15, Color("a8b7bf"))
	box.add_child(subtitle)
	box.add_child(HSeparator.new())
	status = _label("", 15)
	box.add_child(status)
	hint = _label("%s · zwiad pieszy\nPodążaj w stronę punktu InPost." % theia.character_name, 14, Color("d9b775"))
	box.add_child(hint)
	box.add_child(HSeparator.new())
	style_status = _label("", 13, Color("9fb0b8"))
	box.add_child(style_status)
	theia.outline_style_changed.connect(func(_i: int) -> void: _update_style_status())
	theia.painterly_style_changed.connect(func(_i: int) -> void: _update_style_status())
	_update_style_status()
	var footer := ColorRect.new()
	footer.color = Color(0.025, 0.036, 0.046, 0.92)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -60
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(footer)
	controls_hint = _label("", 14, Color("c3cbd0"))
	controls_hint.position = Vector2(32, 18)
	footer.add_child(controls_hint)
	debug_label = _label("", 12, Color("93a6b0"))
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	debug_label.position = Vector2(33, -86)
	root.add_child(debug_label)
	rec_indicator = _label("●  REC", 16, Color("ff5555"))
	rec_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	rec_indicator.position += Vector2(0, 20)
	rec_indicator.visible = recording
	root.add_child(rec_indicator)
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-285, -325)
	pause_panel.custom_minimum_size = Vector2(570, 650)
	pause_panel.add_theme_stylebox_override("panel", style.duplicate())
	root.add_child(pause_panel)
	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", 14)
	pause_panel.add_child(settings)
	settings.add_child(_label("Pauza / Sterowanie", 28))
	controls_picker = OptionButton.new()
	controls_picker.add_item("Klasyczne WASD (domyślne)")
	controls_picker.add_item("Elvenpass — obroty A/D, bieg Q")
	controls_picker.item_selected.connect(func(index: int) -> void: theia.set_control_scheme(index == 0))
	settings.add_child(controls_picker)
	controls_note = _label("", 14, Color("d9b775"))
	settings.add_child(controls_note)
	settings.add_child(_label("Czułość myszy", 14))
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.001
	sensitivity.max_value = 0.012
	sensitivity.step = 0.0005
	sensitivity.value = theia.mouse_sensitivity
	sensitivity.value_changed.connect(func(value: float) -> void: theia.set_sensitivity(value))
	settings.add_child(sensitivity)
	camera_picker = OptionButton.new()
	for preset: Dictionary in Theia.CAMERA_MODES:
		camera_picker.add_item(preset.label)
	camera_picker.select(theia.mode)
	camera_picker.item_selected.connect(func(index: int) -> void: theia.set_camera_mode(index))
	settings.add_child(camera_picker)
	camera_info = _label("", 14, Color("b0bdc6"))
	settings.add_child(camera_info)
	autopilot_button = Button.new()
	autopilot_button.pressed.connect(func() -> void: theia.toggle_autopilot())
	settings.add_child(autopilot_button)
	_autopilot_changed()
	_camera_changed(theia.mode)
	settings.add_child(_label("Niebo · cykl wizualny Ziemi", 14))
	var sky_speed := OptionButton.new()
	for option in ["Zatrzymane", "Spokojnie · 9 minut", "Normalnie · 3 minuty", "Szybko · 45 sekund"]:
		sky_speed.add_item(option)
	sky_speed.select(2)
	sky_speed.item_selected.connect(func(index: int) -> void: lunar_sky.speed_multiplier = [0.0, 1.0 / 3.0, 1.0, 4.0][index])
	settings.add_child(sky_speed)
	var sky_phase := HSlider.new()
	sky_phase.min_value = 0
	sky_phase.max_value = 1
	sky_phase.step = 0.001
	sky_phase.value = lunar_sky.phase
	sky_phase_slider = sky_phase
	sky_phase.tooltip_text = "Położenie Ziemi w cyklu: wschód, górowanie, zachód"
	sky_phase.value_changed.connect(func(value: float) -> void: lunar_sky.apply_phase(value))
	settings.add_child(sky_phase)
	settings.add_child(_label("Styl kreski · klawisz K", 14))
	var outline_picker := OptionButton.new()
	for style_name in theia.OUTLINE_STYLES:
		outline_picker.add_item(style_name)
	outline_picker.select(theia.outline_style)
	outline_picker.item_selected.connect(func(index: int) -> void: theia.set_outline_style(index))
	theia.outline_style_changed.connect(func(index: int) -> void: outline_picker.select(index))
	settings.add_child(outline_picker)
	settings.add_child(_label("Styl malarski · klawisz B", 14))
	var painterly_picker := OptionButton.new()
	for style_name in theia.PAINTERLY_STYLES:
		painterly_picker.add_item(style_name)
	painterly_picker.select(theia.painterly_style)
	painterly_picker.item_selected.connect(func(index: int) -> void: theia.set_painterly_style(index))
	theia.painterly_style_changed.connect(func(index: int) -> void: painterly_picker.select(index))
	settings.add_child(painterly_picker)
	settings.add_child(_label("Nagrywanie wideo · klawisz I", 14))
	rec_button = Button.new()
	rec_button.pressed.connect(_toggle_recording)
	settings.add_child(rec_button)
	_update_rec_button()
	var resume := Button.new()
	resume.text = "Wróć do gry"
	resume.pressed.connect(func() -> void: theia.set_paused(false))
	settings.add_child(resume)
	var quit_button := Button.new()
	quit_button.text = "Zakończ"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	settings.add_child(quit_button)
	pause_panel.hide()
	_controls_changed()
	location_panel = PanelContainer.new()
	location_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	location_panel.position = Vector2(-190, -140)
	location_panel.custom_minimum_size = Vector2(380, 0)
	location_panel.add_theme_stylebox_override("panel", style.duplicate())
	root.add_child(location_panel)
	var loc_box := VBoxContainer.new()
	loc_box.add_theme_constant_override("separation", 12)
	location_panel.add_child(loc_box)
	loc_box.add_child(_label("Wybierz miejsce  ·  N", 22))
	location_picker = OptionButton.new()
	for colony: Dictionary in colonies_data.locations:
		location_picker.add_item(colony.name)
	location_picker.add_item("Własne współrzędne…")
	location_picker.item_selected.connect(_location_picked)
	loc_box.add_child(location_picker)
	custom_row = HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", 10)
	loc_box.add_child(custom_row)
	custom_row.add_child(_label("Szer.", 14))
	custom_lat = SpinBox.new()
	custom_lat.min_value = -90.0
	custom_lat.max_value = 90.0
	custom_lat.step = 0.01
	custom_row.add_child(custom_lat)
	custom_row.add_child(_label("Dł.", 14))
	custom_lon = SpinBox.new()
	custom_lon.min_value = -180.0
	custom_lon.max_value = 180.0
	custom_lon.step = 0.01
	custom_row.add_child(custom_lon)
	custom_row.visible = false
	location_goto_button = Button.new()
	location_goto_button.text = "Leć"
	location_goto_button.visible = false
	location_goto_button.pressed.connect(func() -> void: _jump_globe_to(custom_lat.value, custom_lon.value))
	loc_box.add_child(location_goto_button)
	location_panel.hide()

func _controls_changed() -> void:
	var classic: bool = theia.classic_controls
	controls_picker.select(0 if classic else 1)
	controls_hint.text = "WASD  ruch   SHIFT  bieg   SPACJA  skok   Q  wspinaczka   C  TPP/FPP   V  swobodna kamera   P  autopilot   K  styl kreski   B  styl malarski   I  nagrywanie   L  światła   O  orbita   ESC  pauza" if classic else "W/S  przód/tył   A/D  obrót   Q  bieg / wspinaczka   LPM/C  kamera   V  swobodna   P  autopilot   K  styl kreski   B  styl malarski   I  nagrywanie   L  światła   O  orbita   PPM/ESC  pauza"
	controls_note.text = "WASD + mysz · Shift: bieg · Spacja: skok\nC: widok zza pleców / pierwsza osoba" if classic else "W/S: przód/tył · A/D: obrót o 20°\nQ: bieg · LPM: kamera · PPM: pauza"
	if theia.character_name == "Agnes": controls_note.text += "\nQ przy fasadzie: wspinaczka; wejście na wierzchołek odtwarza zakończenie\nH: płynne przyciemnienie górnej części szybki"
	_camera_changed(theia.mode)

func _update_style_status() -> void:
	if style_status == null:
		return
	style_status.text = "Kreska (K):  %s\nStyl malarski (B):  %s" % [
		theia.OUTLINE_STYLES[theia.outline_style],
		theia.PAINTERLY_STYLES[theia.painterly_style],
	]

func _autopilot_changed() -> void:
	if autopilot_button != null:
		autopilot_button.text = "P / Num Lock: wyłącz autopilota" if theia.autopilot else "P / Num Lock: włącz autopilota"

func _pause_changed(value: bool) -> void:
	pause_panel.visible = value
	terrain.active = not value and not map_mode
	lunar_sky.suspended = value or map_mode
	if value: sky_phase_slider.set_value_no_signal(lunar_sky.phase)

func _camera_changed(index: int) -> void:
	if camera_picker == null: return
	camera_picker.select(index)
	var preset: Dictionary = Theia.CAMERA_MODES[index]
	camera_info.text = "Pole widzenia: %.0f°" % preset.fov
	if index < 3:
		camera_info.text += "\nOdległość: %.1f m  /  Kąt: %.0f°" % [preset.distance, preset.pitch_deg]
	elif index == 4:
		camera_info.text += "\nWASD: lot · Spacja/Ctrl: góra/dół · Shift: szybciej" if theia.classic_controls else "\nW/S: lot  ·  A/D: przesunięcie  ·  Q: szybki lot"
	else:
		camera_info.text += "\nMysz obraca postać i kierunek patrzenia."

func _process(_delta: float) -> void:
	if not is_instance_valid(theia):
		return
	_update_terrain_shadows()
	if landing_busy and globe.approach:
		var altitude := maxf(0.0,get_viewport().get_camera_3d().global_position.y-theia.position.y)
		status.text = "Podejście do lądowania\nWysokość nad celem: %.0f m" % altitude
	elif map_mode:
		var target: Vector2 = globe.target_coordinates()
		status.text = "Cel lądowania: %.4f°, %.4f°\nZbliżenie: W lub kółko myszy" % [target.x, target.y]
	else:
		status.text = "Prędkość    %.1f m/s\nDystans     %.0f m\nGrawitacja  1,62 m/s²" % [Vector2(theia.velocity.x, theia.velocity.z).length(), theia.total_distance]
		status.text += "\nAUTOPILOT · " + ("bieg" if theia.autopilot_running else "marsz") if theia.autopilot else ""
	var source := "GeoServer / cache: %d pobranych" % terrain.stream.downloaded if terrain.stream.enabled else "LOLA + detal proceduralny"
	debug_label.text = "%d FPS   /   KAFLE %d / 121   /   KOLEJKA %d   /   ZWOLNIONE %d   /   %s" % [Engine.get_frames_per_second(), terrain.tiles.size(), terrain.queue.size(), terrain.unloaded_count, source]
	if recording and rec_indicator != null:
		rec_indicator.modulate.a = 0.35 + 0.65 * absf(sin(Time.get_ticks_msec() * 0.004))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M, KEY_O: _toggle_map()
			KEY_TAB: _toggle_coverage()
			KEY_I: _toggle_recording()
			KEY_N: _toggle_location_panel()

func _toggle_map() -> void:
	if theia.paused or landing_busy: return
	map_mode = not map_mode
	lunar_sky.suspended = map_mode
	lunar_sky.set_surface_view(not map_mode)
	if map_mode and globe == null:
		globe = Globe.new()
		globe.terrain = terrain
		globe.roads = roads
		globe.actor = theia
		globe.convoy = lorry
		globe.sector_anchor = Vector2(active_colony.get("latitude", -82.0), active_colony.get("longitude", 30.0))
		globe.local_surface_requested.connect(_enter_local_overlook)
		add_child(globe)
	surface.visible = not map_mode
	theia.enabled = not map_mode
	terrain.active = not map_mode
	globe.visible = map_mode
	if map_mode:
		globe.terrain = terrain
		globe.roads = roads
		globe.actor = theia
		globe.convoy = lorry
		globe.sector_anchor = terrain.latlon_at(theia.position.x, theia.position.z)
		globe.reset_orbit_frame()
		globe._focus_active_sector()
		globe.distance = 4.1
		globe._update_camera()
		globe.camera.make_current()
		if planet_sun_direction == Vector3.ZERO:
			planet_sun_direction = Globe.surface_basis(Vector2(terrain.anchor_lat,terrain.anchor_lon))*lunar_sky.sun_direction
		lunar_sky.sun.look_at_from_position(Vector3.ZERO,-planet_sun_direction,Vector3.UP)
	else:
		theia.camera.make_current()
		_apply_surface_sun()
		location_panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if map_mode or theia.paused else Input.MOUSE_MODE_CAPTURED
	title.text = "Księżyc" if map_mode else active_colony_name
	subtitle.text = "Wybierz dowolny punkt powierzchni i zbliż kamerę" if map_mode else _region_label(active_colony) + "\n" + _format_latlon(active_colony)
	hint.text = "LPM/A/D: wybierz cel · W/kółko: zbliżenie i lądowanie\nS: oddal · Spacja/Ctrl: szerokość · F: punkt startu · N: lista miejsc · O: powrót" if map_mode else "%s · zwiad pieszy · O: lot do innego miejsca" % theia.character_name

func _enter_local_overlook(coordinates: Vector2) -> void:
	if not map_mode or landing_busy:
		return
	landing_busy = true
	globe.set_process(false)
	globe.set_process_unhandled_input(false)
	hint.text = "Podejście do lądowania: %.4f°, %.4f°" % [coordinates.x, coordinates.y]
	# Keep the actor (and UI signal connections), replacing only the local world.
	theia.stop_autopilot()
	theia.set_physics_process(false)
	surface.remove_child(theia)
	for child in surface.get_children():
		child.free()
	var destination := _landing_destination(coordinates)
	_build_surface(destination.name, destination)
	theia.footprints.clear()
	theia.footprint_root = Node3D.new()
	surface.add_child(theia.footprint_root)
	var ll := Vector2(float(destination.latitude), float(destination.longitude))
	var delta_lon := wrapf(coordinates.y - ll.y, -180.0, 180.0)
	var point := Vector3(deg_to_rad(delta_lon) * 1737400.0 * cos(deg_to_rad(ll.x)), 0.0, -deg_to_rad(coordinates.x - ll.x) * 1737400.0)
	# Authored colony centres may contain buildings: use their established landing
	# approach when the chosen point is directly on a colony marker.
	if not destination.get("wilderness", false) and Vector2(point.x, point.z).length() < 100.0:
		point = _player_start()
	terrain.update_focus(point)
	while not terrain.has_ground(point):
		terrain._build_next()
		await get_tree().process_frame
	theia.position = Vector3(point.x, terrain.height_at(point.x, point.z) + 0.3, point.z)
	theia.last_foot = theia.position
	theia.velocity = Vector3.ZERO
	theia.terrain = terrain
	globe.terrain = terrain
	globe.roads = roads
	globe.actor = theia
	globe.convoy = lorry
	globe.begin_surface_frame(terrain)
	_apply_surface_sun()
	surface.visible = true
	terrain.active = true
	terrain.visible = false
	terrain.material.set_shader_parameter("detail_blend", 0.0)
	# The spherical meso surface remains visible around the detailed local tiles.
	# The flat walking horizon is already streaming, but is revealed at ground level.
	var horizon: Node3D = surface.get_node("GlobalDemHorizon")
	horizon.visible = false
	theia.enabled = false
	globe.set_process(true)
	var start_eye: Vector3 = globe.camera.global_position
	globe.meso.reference_radius = 1.0 + (terrain.base_elevation+theia.position.y)/1737400.0
	var elapsed := 0.0
	while not globe.meso.ready_for_view:
		await get_tree().process_frame
	while elapsed < Approach.DURATION:
		await get_tree().process_frame
		var dt := minf(get_process_delta_time(), 0.1)
		# Parent meshes cover unfinished LODs. Slow the flight under load without
		# stopping at every quadtree boundary.
		elapsed = minf(Approach.DURATION,elapsed+dt*clampf(24.0/maxf(24.0,globe.meso.pending.size()),0.25,1.0))
		var pose := Approach.pose(elapsed,start_eye,theia.position)
		var p: Vector3 = pose.position
		# Camera clearance follows the terrain along the whole glide, not just the
		# endpoint. A lander viewpoint must stay above intervening crater rims.
		p.y = maxf(p.y,terrain.height_at(p.x,p.z)+120.0)
		globe.camera.global_position = p
		globe.camera.look_at(p+Vector3(pose.look),Vector3.FORWARD)
		globe.distance = globe.camera.position.length()
		var altitude := p.y-theia.position.y
		var detail_weight := 1.0-smoothstep(400.0,1200.0,altitude)
		globe.meso.detail_blend = detail_weight
		terrain.material.set_shader_parameter("detail_blend",detail_weight)
		terrain.visible = altitude < 600.0 and terrain.queue.is_empty()
		if terrain.queue.is_empty() and terrain.visible:
			globe.meso.local_hole = Vector4((terrain.center.x-5)*64.0, (terrain.center.y-5)*64.0, (terrain.center.x+6)*64.0, (terrain.center.y+6)*64.0)
	# Transfer the camera at exactly the same position/FOV. Local geometry has
	# already been on screen throughout the approach; this is only camera ownership.
	var eye: Vector3 = globe.camera.global_position
	var look: Vector3 = -globe.camera.global_basis.z.normalized()
	var approach_fov: float = globe.camera.fov
	map_mode = false
	terrain.visible = true
	terrain.material.set_shader_parameter("detail_blend", 1.0)
	lunar_sky.suspended = false
	lunar_sky.set_surface_view(true)
	# Keep the spherical background throughout the oblique final descent.
	globe.meso.detail_blend = 1.0
	globe.set_process_unhandled_input(true)
	title.text = active_colony_name
	subtitle.text = _region_label(active_colony) + "\n" + _format_latlon(active_colony)
	theia.set_camera_mode(4)
	var look_target := theia.position
	theia.free_position = eye
	theia.free_yaw = atan2(look.x,look.z)
	theia.free_pitch = asin(clampf(look.y,-1.0,1.0))
	theia._update_camera()
	theia.camera.fov = approach_fov
	theia.camera.make_current()
	# A straight lerp from dead overhead would read as almost perfectly vertical
	# for most of these 10 s -- eye and look_target share the same x/z, so only
	# the final metres actually curve toward the (0,8,7) framing. Bezier through
	# two offset control points instead: same fixed start (no pop at handoff) and
	# same fixed end, but the path banks out sideways in between, so relief is
	# seen at a grazing angle for the whole final approach, not just its last beat.
	var swoop_a := eye + Vector3(90.0, -55.0, 25.0)
	var swoop_b := look_target + Vector3(35.0, 60.0, 35.0)
	var descent := create_tween().set_parallel(true)
	descent.tween_property(theia, "free_pitch", -0.86, 10.0).set_trans(Tween.TRANS_SINE)
	descent.tween_method(func(t: float) -> void:
		var p: Vector3 = eye.bezier_interpolate(swoop_a, swoop_b, look_target + Vector3(0, 8, 7), t)
		p.y = maxf(p.y, terrain.height_at(p.x, p.z) + 8.0)
		theia.free_position = p
		theia._update_camera(), 0.0, 1.0, 10.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await descent.finished
	globe.visible = false
	horizon.visible = true
	theia.enabled = true
	theia.set_physics_process(true)
	theia.set_camera_mode(1)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	landing_busy = false
	hint.text = "Lądowanie zakończone · WASD: eksploracja · O: następny lot"

func _apply_surface_sun() -> void:
	if planet_sun_direction == Vector3.ZERO: return
	lunar_sky.sun_override_direction = Globe.surface_basis(Vector2(terrain.anchor_lat,terrain.anchor_lon)).transposed()*planet_sun_direction
	lunar_sky.apply_phase(lunar_sky.phase)

func _update_terrain_shadows() -> void:
	var sun: DirectionalLight3D = lunar_sky.sun
	var orbit: bool = map_mode and globe != null and not globe.approach
	if orbit:
		# Globe units are lunar radii. A 50,000-unit map would waste its entire
		# resolution on empty space; fit all cascades around the visible globe.
		sun.directional_shadow_max_distance = minf(80.0,globe.distance+2.0)
		sun.directional_shadow_split_1 = 0.2
		sun.directional_shadow_split_2 = 0.5
		sun.directional_shadow_split_3 = 0.75
		sun.shadow_normal_bias = 0.15
	else:
		var altitude := maxf(0.0,get_viewport().get_camera_3d().global_position.y-theia.position.y)
		var high := smoothstep(500.0,8000.0,altitude) if landing_busy else 0.0
		sun.directional_shadow_max_distance = maxf(50000.0,altitude*1.8) if landing_busy else 50000.0
		sun.directional_shadow_split_1 = lerpf(0.0032,0.08,high)
		sun.directional_shadow_split_2 = lerpf(0.02,0.25,high)
		sun.directional_shadow_split_3 = lerpf(0.16,0.55,high)
		sun.shadow_normal_bias = 1.0

func _landing_destination(coordinates: Vector2) -> Dictionary:
	var radial := Vector3(cos(deg_to_rad(coordinates.x)) * sin(deg_to_rad(coordinates.y)), sin(deg_to_rad(coordinates.x)), cos(deg_to_rad(coordinates.x)) * cos(deg_to_rad(coordinates.y)))
	for colony: Dictionary in colonies_data.locations:
		var lat := deg_to_rad(float(colony.latitude))
		var lon := deg_to_rad(float(colony.longitude))
		var direction := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
		if radial.angle_to(direction) * 1737400.0 < 1200.0:
			return colony
	return {"name": "Landing_%.5f_%.5f" % [coordinates.x, coordinates.y], "latitude": coordinates.x, "longitude": coordinates.y, "region": "Obszar eksploracji", "wilderness": true}

func _toggle_coverage() -> void:
	coverage = not coverage
	terrain.set_coverage(coverage)
	hint.text = "Turkus: łagodny regolit\nOchra: stoki / odsłonięcia skał" if coverage else "%s · zwiad pieszy\nPodążaj w stronę punktu InPost." % theia.character_name

func _toggle_location_panel() -> void:
	if not map_mode or theia.paused:
		return
	location_panel.visible = not location_panel.visible
	if location_panel.visible:
		var target: Vector2 = globe.target_coordinates()
		custom_lat.value = target.x
		custom_lon.value = target.y
		location_picker.select(0)
		custom_row.visible = false
		location_goto_button.visible = false

## A real colony jumps the view there immediately; the last entry ("Własne
## współrzędne…") instead reveals the lat/lon fields and waits for "Leć" --
## picking it shouldn't fly anywhere on its own.
func _location_picked(index: int) -> void:
	var custom: bool = index >= (colonies_data.locations as Array).size()
	custom_row.visible = custom
	location_goto_button.visible = custom
	if not custom:
		var colony: Dictionary = colonies_data.locations[index]
		_jump_globe_to(float(colony.latitude), float(colony.longitude))

func _jump_globe_to(lat: float, lon: float) -> void:
	globe.yaw = deg_to_rad(lon)
	globe.pitch = deg_to_rad(lat)
	globe.surface_transition_sent = false
	globe._update_camera()
	location_panel.hide()

func _cycle_camera() -> void:
	theia.cycle_camera()

func _capture() -> void:
	theia.set_camera_mode(1)
	await get_tree().create_timer(8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/surface.png")
	theia.set_paused(true)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/camera_settings.png")
	theia.set_paused(false)
	theia.set_camera_mode(3)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/first_person.png")
	_toggle_map()
	await get_tree().create_timer(2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/globe.png")
	get_tree().quit()

func _capture_globe() -> void:
	await get_tree().create_timer(3.0).timeout
	_toggle_map()
	var farside := "--farside" in OS.get_cmdline_user_args()
	globe.yaw = deg_to_rad(163.0 if farside else 35.0)
	globe.pitch = deg_to_rad(-5.0) if farside else -1.32
	globe.distance = 3.1 if farside else 2.15
	globe._update_camera()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/globe_farside.png" if farside else "res://../artifacts/globe_silesia.png")
	get_tree().quit()

func _capture_fox() -> void:
	theia.set_outline_style(0)
	await get_tree().create_timer(1.0).timeout
	var fox := (load("res://assets/colonies/tycho/modules/fox.glb") as PackedScene).instantiate() as Node3D
	surface.add_child(fox)
	# Measure at scale=1/position=0 (bind pose; animation not played here --
	# this capture only needs the static look, see _capture_fox_wander() for
	# the animated/in-park view), then rescale and recentre around the AABB's
	# centre rather than its corner so the result doesn't depend on where the
	# model's pivot happens to sit.
	var box := AABB()
	var seeded := false
	for m: MeshInstance3D in fox.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null: continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		box = b if not seeded else box.merge(b)
		seeded = true
	# There is no 100x skin-deformation factor -- that theory was wrong. The
	# raw box is measured correctly; scaling straight to the target size and
	# THEN re-measuring (below) is the only fix actually needed. box.size.z
	# is confirmed (by comparing proportions against the source Blender mesh)
	# to be the standing-height axis for this asset's bind-pose AABB -- scale
	# off of it directly so the fox comes out ~30 cm tall, not off the
	# diagonal (which mixes in body length and is a worse proxy for height).
	var scale := 0.30 / maxf(box.size.z, 0.000000001)
	fox.scale = Vector3.ONE * scale
	var spot := Vector3(TYCHO_PLAYER_START.x + 4.0, 0, TYCHO_PLAYER_START.z)
	var ground := Vector3(spot.x, terrain.height_at(spot.x, spot.z), spot.z)
	# box.position.z is the lowest point's offset from the model's own local
	# origin (measured at scale=1) -- it's slightly positive (paws sit just
	# above local (0,0,0)), so placing the origin at ground height alone
	# leaves the paws hovering by that offset once scaled. Shift down by it.
	ground.y -= box.position.z * scale
	fox.position = ground
	await get_tree().process_frame
	# Re-measure post-scale: the bind-pose box's tiny offset from the local
	# origin gets amplified by `scale` right along with its size, so the
	# model's true centre can land far from `fox.position` -- frame the
	# camera on the freshly measured box, not a fixed offset from `ground`.
	var scaled_box := AABB()
	seeded = false
	for m: MeshInstance3D in fox.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null: continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		scaled_box = b if not seeded else scaled_box.merge(b)
		seeded = true
	var center: Vector3 = scaled_box.position + scaled_box.size * 0.5
	var radius: float = maxf(scaled_box.size.length(), 1.5) * 0.45
	var cam_pos := center + Vector3(radius, radius * 0.65, radius)
	cam_pos.y = maxf(cam_pos.y, terrain.height_at(cam_pos.x, cam_pos.z) + 0.5)
	var cam := Camera3D.new()
	surface.add_child(cam)
	cam.position = cam_pos
	cam.look_at(center)
	cam.make_current()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/fox_preview.png")
	get_tree().quit()

func _capture_fox_wander() -> void:
	theia.set_outline_style(0)
	# TychoCity builds ground_details (lawn/grass/fox) automatically once the
	# player's start position is within range -- no manual trigger needed,
	# just wait for it and for a couple of walk-cycle frames to play so the
	# screenshot shows the ANIMATED pose (paw placement mid-stride), not the
	# static bind pose _capture_fox() uses.
	await get_tree().create_timer(3.0).timeout
	var foxes := get_tree().get_nodes_in_group("fox_npc")
	if foxes.is_empty():
		push_error("fox_npc not found -- TychoCity ground_details not built yet?")
		get_tree().quit()
		return
	var fox: Node3D = foxes[0]
	for i in 2:
		await get_tree().create_timer(2.0).timeout
		var cam := Camera3D.new()
		surface.add_child(cam)
		var p := fox.global_position
		cam.position = p + Vector3(1.1, 0.7, 1.1)
		cam.look_at(p + Vector3(0, 0.15, 0))
		cam.make_current()
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../artifacts/fox_wander_%d.png" % i)
		cam.queue_free()
	get_tree().quit()

func _capture_rain_outline() -> void:
	theia.set_outline_style(0)
	await get_tree().create_timer(2.0).timeout
	var weather := ground_details_node().find_child("TychoWeather", true, false)
	weather.rain_strength = 1.0
	for i in weather.drops.size():
		var drop: Dictionary = weather.drops[i]
		weather._spawn_drop(drop, true)
		weather.drops[i] = drop
	weather._update_drops(0.15)
	# Freeze the drops in place for the whole comparison -- otherwise each
	# style capture is a DIFFERENT time instant with rain in different
	# positions, and a pixel that "lost" its rain between two screenshots
	# could just be a drop that moved on its own, not the outline erasing it.
	weather.set_physics_process(false)
	var cam := Camera3D.new()
	surface.add_child(cam)
	var site_center: Vector2 = preload("res://scripts/tycho_site.gd").CENTER
	var rain_world: Vector2 = site_center + Vector2(weather.rain_center)
	var center := Vector3(rain_world.x, terrain.city_level + 8.0, rain_world.y)
	cam.position = center + Vector3(3.0, 1.5, 3.0)
	cam.look_at(center)
	cam.make_current()
	for style in ["off", "comic", "moebius"].size():
		theia.set_outline_style(style)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../artifacts/rain_outline_%d_%s.png" % [style, ["off", "comic", "moebius"][style]])
	get_tree().quit()

func ground_details_node() -> Node:
	var city := get_tree().get_root().find_child("TychoCity", true, false)
	return city.ground_details

func _capture_run_jump() -> void:
	# Agnes begins on Tycho's InPost highway approach, then runs and jumps.
	# Godot's --write-movie option owns fixed-rate video capture for this shot.
	theia.set_control_scheme(true)
	theia.set_camera_mode(1)
	theia.position = Vector3(TYCHO_PLAYER_START.x, terrain.height_at(TYCHO_PLAYER_START.x, TYCHO_PLAYER_START.z) + 0.15, TYCHO_PLAYER_START.z)
	theia.velocity = Vector3.ZERO
	theia.visual_yaw = 0.0
	theia.yaw = PI
	theia._update_camera()
	await get_tree().create_timer(1.0).timeout
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await get_tree().create_timer(1.35).timeout
	theia._try_jump()
	await get_tree().create_timer(2.15).timeout
	Input.action_release("move_forward")
	Input.action_release("sprint")
	print("RUN_JUMP MOVIE: complete")
	get_tree().quit()

func _smoke_test() -> void:
	if active_colony_name == "Tycho Station":
		assert(theia.character_name == "Agnes", "Agnes must be the default explorer")
		assert(Vector2(theia.position.x, theia.position.z).distance_to(Vector2(TYCHO_PLAYER_START.x, TYCHO_PLAYER_START.z)) < 0.01, "Agnes must begin at the Tycho station entrance")
		# The dead southbound access stub is gone: Tycho's one live highway is the
		# 22 km InPost spur, so no interchange is built here.
		for tycho_tile in roads.descriptors_by_tile.values():
			for tycho_seg: Dictionary in tycho_tile:
				assert(not str(tycho_seg.route).contains("link") and not str(tycho_seg.route).contains("junction"), "Tycho's single spur must not build an interchange")
	var original_phase: float = lunar_sky.phase
	var fixed_stars: PackedVector4Array = lunar_sky.material.get_shader_parameter("stars")
	assert(fixed_stars.size() == 32, "Bright-star catalog must be loaded")
	for star in fixed_stars:
		assert(absf(Vector3(star.x, star.y, star.z).length() - 1.0) < 0.0001 and star.w > 0, "Stars need unit directions and positive brightness")
	lunar_sky.apply_phase(0.25)
	assert(lunar_sky.earth_altitude_degrees > lunar_sky.earth_diameter_degrees * 0.5, "Earth must rise fully above horizon")
	lunar_sky.apply_phase(0.75)
	assert(lunar_sky.material.get_shader_parameter("stars") == fixed_stars, "Earth's cycle must not rotate the stars")
	assert(lunar_sky.earth_altitude_degrees < -lunar_sky.earth_diameter_degrees * 0.5, "Earth must set fully below horizon")
	assert(lunar_sky.sun.global_basis.z.dot(lunar_sky.sun_direction) > 0.999, "Sun disk must match the direction of illumination")
	lunar_sky.apply_phase(original_phase)
	theia.set_control_scheme(false)
	await get_tree().create_timer(3).timeout
	assert(theia.is_on_floor(), "Theia must land on the lunar collision mesh")
	assert(theia.players.size() == theia.model_paths.size(), "All character animation models must load")
	if theia.character_name == "Agnes":
		assert(theia.active_visual == 4 and theia.players[4].speed_scale > 0, "Agnes must play her idle animation while standing")
	var start := theia.position
	Input.action_press("move_forward")
	await get_tree().create_timer(2).timeout
	Input.action_release("move_forward")
	assert(theia.position.distance_to(start) > 3.0, "Walking input must move Theia over terrain")
	# Elvenpass controls: A/D turn in place, Q runs without W, free camera leaves the actor still.
	var before_turn: Vector3 = theia.position
	var facing: float = theia.visual_yaw
	theia._start_turn(-1)
	await get_tree().create_timer(theia.turn_duration + 0.1).timeout
	assert(absf(wrapf(theia.visual_yaw - facing, -PI, PI) - deg_to_rad(20)) < 0.001, "A must turn left by 20 degrees")
	assert(Vector2(theia.position.x - before_turn.x, theia.position.z - before_turn.z).length() < 0.05, "Turning must not strafe")
	theia._start_turn(1)
	await get_tree().create_timer(theia.turn_duration + 0.1).timeout
	assert(absf(wrapf(theia.visual_yaw - facing, -PI, PI)) < 0.001, "D must turn right by 20 degrees")
	# The walk-forward check above already spent most of the clear ground between
	# the station entrance and the dome's gate bulkhead: continuing to run from
	# here rams Theia into that collision within the first physics tick, reading
	# velocity that a real wall stopped, not one Q failed to produce. This is only
	# an input/velocity check, so give it its own clear run back at the entrance.
	theia.position = start
	theia.velocity = Vector3.ZERO
	Input.action_press("run_forward")
	await get_tree().create_timer(0.5).timeout
	assert(Vector2(theia.velocity.x, theia.velocity.z).length() > 4.5, "Q alone must run forward")
	Input.action_release("run_forward")
	for i in 5:
		theia.set_camera_mode(i)
		assert(is_equal_approx(theia.camera.fov, float(Theia.CAMERA_MODES[i].fov)), "Elvenpass camera FOV must match")
	var actor: Vector3 = theia.position
	var eye: Vector3 = theia.camera.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(0.25).timeout
	Input.action_release("move_forward")
	assert(theia.position.is_equal_approx(actor), "Free camera must not move Theia")
	assert(theia.camera.global_position.distance_to(eye) > 1.0, "W must fly the free camera")
	theia.set_camera_mode(3)
	theia.set_paused(true)
	Input.action_press("run_forward")
	var paused_sky_phase: float = lunar_sky.phase
	await get_tree().create_timer(0.2).timeout
	Input.action_release("run_forward")
	assert(theia.position.is_equal_approx(actor), "Pause must freeze movement")
	assert(lunar_sky.phase == paused_sky_phase, "Pause must freeze the sky cycle")
	theia.set_paused(false)
	# Classic profile: ground movement is camera-relative, diagonals are normalized,
	# Shift alone is stationary and FPP strafing does not turn the character.
	theia.position = Vector3(0, terrain.height_at(0, 0) + 0.1, 0)
	theia.set_control_scheme(true)
	await get_tree().create_timer(0.3).timeout
	var classic_start: Vector3 = theia.position
	Input.action_press("sprint")
	await get_tree().create_timer(0.2).timeout
	assert(Vector2(theia.velocity.x, theia.velocity.z).length() < 0.01, "Shift alone must not move")
	Input.action_press("move_forward")
	await get_tree().create_timer(0.5).timeout
	assert(Vector2(theia.velocity.x, theia.velocity.z).length() > 4.5, "Shift+W must sprint")
	Input.action_press("move_right")
	await get_tree().create_timer(0.2).timeout
	assert(Vector2(theia.velocity.x, theia.velocity.z).length() <= 5.21, "Diagonals must not increase speed")
	Input.action_release("move_forward")
	Input.action_release("move_right")
	Input.action_release("sprint")
	assert(theia.position.distance_to(classic_start) > 2.0, "Classic movement must work")
	theia.cycle_camera()
	assert(theia.mode == 3, "C must switch to first person")
	var strafe_facing: float = theia.visual_yaw
	Input.action_press("move_right")
	await get_tree().create_timer(0.3).timeout
	Input.action_release("move_right")
	assert(is_equal_approx(theia.visual_yaw, strafe_facing), "First-person D must strafe without rotating")
	theia.cycle_camera()
	assert(theia.mode == 1, "C must return to third person")
	# Autopilot continues moving the actor independently of the free camera.
	theia.position = Vector3(0, terrain.height_at(0, 0) + 0.1, 0)
	theia.velocity = Vector3.ZERO
	theia.visual_yaw = PI
	theia.toggle_autopilot()
	var pilot_start: Vector3 = theia.position
	theia.toggle_free_camera()
	var free_start: Vector3 = theia.camera.global_position
	Input.action_press("move_right")
	await get_tree().create_timer(1).timeout
	Input.action_release("move_right")
	assert(theia.autopilot and theia.position.distance_to(pilot_start) > 2.0, "Autopilot must keep walking in free-camera mode")
	assert(theia.camera.global_position.distance_to(free_start) > 4.0, "Camera must move independently while autopilot walks")
	assert(absf(theia.position.x - pilot_start.x) < 0.1, "Free-camera strafing must not steer autopilot")
	theia.set_paused(true)
	var paused_pilot: Vector3 = theia.position
	await get_tree().create_timer(0.2).timeout
	assert(theia.position.is_equal_approx(paused_pilot), "Pause must also freeze autopilot")
	theia.set_paused(false)
	theia.toggle_free_camera()
	var manual := InputEventKey.new()
	manual.physical_keycode = KEY_W
	manual.pressed = true
	theia._unhandled_input(manual)
	assert(not theia.autopilot, "Manual WASD must take control back outside free camera")
	# Test physical movement across actual tile boundaries, then eviction.
	for p in [Vector3(65, 0, 0), Vector3(193, 0, 0), Vector3(-129, 0, -65)]:
		theia.enabled = false
		theia.position = Vector3(p.x, terrain.height_at(p.x, p.z) + 0.1, p.z)
		terrain.update_focus(theia.position)
		await get_tree().create_timer(2.5).timeout
		assert(terrain.has_ground(theia.position), "Streaming must prepare destination collision")
		assert(terrain.tiles.size() <= 121, "Tile memory must stay bounded")
		var query := PhysicsRayQueryParameters3D.create(theia.position + Vector3.UP * 10, theia.position - Vector3.UP * 30)
		query.exclude = [theia.get_rid()]
		assert(not get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Tile collision ray must hit")
	assert(terrain.unloaded_count > 0, "Distant tiles must be evicted")
	theia.position = start
	_toggle_map()
	assert(globe.colony_data.locations.size() == 15)
	assert(globe.highways != null and globe.highways.mesh.get_surface_count() >= 3, "Globe must trace the baked highway routes")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(globe.convoy_dot.position.length() > 0.5 and globe.actor_dot.position.length() > 0.5, "Globe must plot Agnes and the convoy live")
	globe._focus_active_sector()
	globe.distance = 1.04
	globe._process(0.0)
	while landing_busy:
		await get_tree().process_frame
	assert(not map_mode and theia.mode == 1, "Descent must return control on the surface")
	assert(terrain.has_ground(theia.position), "Landing must wait for collision tiles")
	print("SMOKE PASS: Sun/Earth/stars, classic WASD/sprint/strafe, Elvenpass controls, cameras, independent autopilot, pause, streaming, globe with highways and live units")
	get_tree().quit()

func _capture_sky() -> void:
	await get_tree().create_timer(6).timeout
	lunar_sky.suspended = true
	theia.set_camera_mode(3)
	theia.visual_yaw = PI
	theia.fpv_pitch = deg_to_rad(5)
	for entry in [[0.12, "sky_earthrise"], [0.25, "sky_earth_high"], [0.75, "sky_earthset"]]:
		lunar_sky.apply_phase(entry[0])
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../artifacts/%s.png" % entry[1])
	theia.fpv_pitch = deg_to_rad(30)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/starfield.png")
	theia.set_paused(true)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/camera_settings.png")
	get_tree().quit()

func _lorry_test() -> void:
	await get_tree().create_timer(2.0).timeout
	assert(is_instance_valid(lorry), "Lorry must be part of the surface scene")
	assert(lorry is VehicleBody3D, "Rover must be a real rigid vehicle body")
	assert(lorry.vwheels.size() == 4, "Rover must run four VehicleWheel3D suspensions")
	for vw in lorry.vwheels:
		assert(vw is VehicleWheel3D, "Each corner must be a VehicleWheel3D")
	assert(lorry.headlights.size() == 2 and lorry.light_mode == 1, "Rover must start with paired low beams")
	assert(is_equal_approx(lorry.model.scale.x, Lorry.ROVER_SCALE) and is_instance_valid(lorry.pod), "Rover is one object: scaled donor chassis plus the fitted cabin pod")

	var start_pos: Vector3 = lorry.global_position
	var first_tracks: int = lorry.track_count
	var best_grounded := 0
	var max_air := 0.0
	var max_tilt := 0.0
	for s in 24:
		var g := 0
		for vw in lorry.vwheels:
			if vw.is_in_contact():
				g += 1
		best_grounded = maxi(best_grounded, g)
		max_air = maxf(max_air, lorry.global_position.y - terrain.height_at(lorry.global_position.x, lorry.global_position.z))
		max_tilt = maxf(max_tilt, rad_to_deg(lorry.global_basis.y.angle_to(Vector3.UP)))
		await get_tree().create_timer(0.25).timeout
	assert(best_grounded >= 3, "Suspension must keep the rover on the ground, not drop it through or float it")
	assert(max_air < 2.5, "Rover must stay on the terrain, not launch off crests")
	assert(max_tilt < 20.0, "Firmed suspension and upright assist must hold the lean down (was %.1f deg)" % max_tilt)
	assert(lorry.global_position.distance_to(start_pos) > 2.0, "Rover must carry itself along the route under engine force")
	assert(lorry.linear_velocity.length() > 0.5, "Moving rover must hold real momentum")
	var spinning := false
	for vw in lorry.vwheels:
		if absf(vw.get_rpm()) > 5.0:
			spinning = true
	assert(spinning, "Wheels must roll while the rover drives")
	assert(lorry.global_basis.y.angle_to(Vector3.UP) < deg_to_rad(40.0), "Rover must stay upright on the terrain")

	lorry.set_light_mode(2)
	assert(lorry.headlights[0].visible and lorry.headlights[0].spot_range == 82.0, "High beams must extend the rover light range")
	lorry.set_light_mode(0)
	assert(not lorry.headlights[0].visible, "Rover headlights must switch off")
	assert(lorry.track_count > first_tracks, "Moving rover must stamp wheel tracks")
	assert(lorry.track_root.get_parent() == surface, "Tracks must remain on terrain after the rover moves")
	assert(lorry.track_root.get_child_count() == 1, "All wheel marks must share one MultiMesh draw call")
	print("LORRY PASS: rigid VehicleBody3D, four suspensions on the ground, momentum, rolling wheels, persistent tracks")
	get_tree().quit()

func _capture_lorry() -> void:
	await get_tree().create_timer(4.0).timeout
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 42
	cam.make_current()
	for shot in [["side", Vector3(1.0, 0.16, 0.08)], ["corner", Vector3(0.8, 0.34, 0.7)], ["rear", Vector3(-0.15, 0.22, -1.0)]]:
		var focus: Vector3 = lorry.global_position + Vector3(0, 2.2, 0)
		cam.global_position = focus + (shot[1] as Vector3).normalized() * 25.0
		cam.look_at(focus)
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../artifacts/lorry_%s.png" % shot[0])
		await get_tree().create_timer(1.4).timeout
	get_tree().quit()

func _road_test() -> void:
	await get_tree().create_timer(1.0).timeout
	assert(is_instance_valid(roads), "Road streamer must be added with the terrain")
	assert(roads.descriptors_by_tile.size() > 0, "Silesia routes must be indexed by terrain tile")
	assert(roads.loaded.size() > 0 and roads.full_segment_count > 0, "Nearby road decks must stream with collision")
	assert(is_equal_approx(roads.lane_width, Lorry.highway_vehicle_width() * 2.0))
	var actual_max_grade := 0.0
	var grade_by_route := {}
	for tile in roads.descriptors_by_tile.values():
		for descriptor: Dictionary in tile:
			var delta: Vector3 = descriptor.b - descriptor.a
			var grade := absf(delta.y) / Vector2(delta.x, delta.z).length()
			actual_max_grade = maxf(actual_max_grade, grade)
			grade_by_route[descriptor.route] = maxf(grade_by_route.get(descriptor.route, 0.0), grade)
	for route in grade_by_route:
		print("ROUTE GRADE  %-28s %.2f%%" % [route, grade_by_route[route] * 100.0])
	print("%s MAX GRADE: %f" % [active_colony_name.to_upper(), actual_max_grade])
	assert(actual_max_grade <= 0.0602, "Actual local road grades must stay below 6% within mesh precision")
	var lit_routes := {}
	var lamp_count := 0
	for tile in roads.lamp_descriptors_by_tile.values():
		for lamp: Dictionary in tile:
			lit_routes[lamp.route] = true
			lamp_count += 1
	var paved_length := 0.0
	for tile in roads.descriptors_by_tile.values():
		for descriptor: Dictionary in tile:
			assert(lit_routes.has(descriptor.route), "Every local road, connector and ramp must have lamps")
			if descriptor.get("kind") != "junction":
				paved_length += (descriptor.b as Vector3).distance_to(descriptor.a)
	# Two lamp lines at 40 m spacing; allow for junction-clear gaps and rounding.
	# Silesia's dense network keeps the historical > 100 floor; a lean spur sector
	# (Tycho: one highway split by the crater lift) is held to its own length.
	var lamp_floor: int = mini(100, int(paved_length / 40.0))
	assert(lamp_count > lamp_floor, "Lamps must cover full local routes, not just the junction")
	print("ROAD LAMPS: ", lamp_count, " across ", lit_routes.size(), " routes/junctions")
	var current_tiles: int = roads.loaded.size()
	terrain.update_focus(Vector3(512, terrain.height_at(512, 0), 0))
	await get_tree().create_timer(0.2).timeout
	assert(roads.center == terrain.center, "Road streamer must follow terrain focus")
	assert(roads.loaded.size() <= current_tiles, "Road tiles outside the streaming range must unload")
	print("ROAD PASS: local sector road index, near collision decks and streamed LOD")
	get_tree().quit()

func _dem_probe() -> void:
	await get_tree().create_timer(2.0).timeout
	print("DEM PROBE ", active_colony_name, " anchor ", active_colony.get("latitude"), "/", active_colony.get("longitude"))
	for p in [Vector2(0, 0), Vector2(200, 0), Vector2(-200, 0), Vector2(0, 200), Vector2(0, -200), Vector2(600, 400), Vector2(-800, -600), Vector2(1200, 0)]:
		var ll: Vector2 = terrain.latlon_at(p.x, p.y)
		print("  local(%.0f,%.0f)  latlon(%.5f,%.5f)  height_at=%.2f" % [p.x, p.y, ll.x, ll.y, terrain.height_at(p.x, p.y)])
	get_tree().quit()

func _capture_road() -> void:
	await get_tree().create_timer(1.0).timeout
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 55
	cam.make_current()
	var focus: Vector3 = roads.interchange_center
	if focus == Vector3.ZERO and not roads.descriptors_by_tile.is_empty():
		# Sectors without an interchange (a single spur, e.g. Tycho) frame the
		# first baked road segment instead of the origin.
		for tile in roads.descriptors_by_tile.values():
			focus = (tile[0].a as Vector3 + tile[0].b as Vector3) * 0.5
			break
	theia.set_physics_process(false)
	theia.set_process(false)
	terrain.update_focus(focus)
	var lamp_preview := "--lamps" in OS.get_cmdline_user_args()
	if lamp_preview:
		for light in find_children("*", "DirectionalLight3D", true, false):
			light.light_energy = 0.03
		for env in find_children("*", "WorldEnvironment", true, false):
			env.environment.ambient_light_energy = 0.08
	cam.global_position = focus + (Vector3(45, 23, 55) if lamp_preview else Vector3(180, 210, 230))
	cam.look_at(focus)
	for frame in 150:
		await get_tree().process_frame
		if terrain.queue.is_empty():
			break
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../artifacts/highway_lights.png" if lamp_preview else "res://../artifacts/highway.png")
	get_tree().quit()
