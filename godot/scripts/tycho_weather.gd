extends Node3D
## Local indoor weather under the Tycho dome: clouds gather, rain falls over a
## moving district, and drops bounce once from real collision surfaces.
const Dome := preload("res://scripts/tycho_dome.gd")
const GRAVITY := 1.62
const DROP_COUNT := 112
const LOCAL_RAIN_RADIUS := 18.0
const CLOUD_BUILD_END := 15.0
const RAIN_END := 55.0
const CYCLE_SECONDS := 75.0

var terrain: Node3D
var weather_time := 12.0
var rain_strength := 0.0
var cloud_amount := 0.0
var rain_center := Vector2(-18.0, -18.0)
var cloud_height := 64.0
var drops: Array[Dictionary] = []
var drop_meshes: MultiMesh
var rng := RandomNumberGenerator.new()
var previous_phase := 12.0
var bounce_count := 0

func _ready() -> void:
	name = "TychoWeather"
	rng.seed = 741903
	set_meta("cycle_seconds", CYCLE_SECONDS)
	set_meta("drop_count", DROP_COUNT)
	set_meta("gravity", GRAVITY)
	set_meta("local_radius", LOCAL_RAIN_RADIUS)
	_build_rain()
	_choose_rain_cell(false)
	_update_weather_strengths()

func _physics_process(delta: float) -> void:
	weather_time = fmod(weather_time + delta, CYCLE_SECONDS)
	var rain_started := previous_phase < CLOUD_BUILD_END and weather_time >= CLOUD_BUILD_END
	if weather_time < previous_phase:
		_choose_rain_cell(true)
	_update_weather_strengths()
	var volumetric_clouds := get_parent().get_node_or_null("TychoVolumetricClouds")
	if volumetric_clouds != null:
		volumetric_clouds.set_weather_amount(cloud_amount)
	if rain_started:
		for i in DROP_COUNT:
			var drop: Dictionary = drops[i]
			_spawn_drop(drop, true)
			drops[i] = drop
	_update_drops(delta)
	previous_phase = weather_time

func _update_weather_strengths() -> void:
	if weather_time < CLOUD_BUILD_END:
		cloud_amount = smoothstep(0.0, CLOUD_BUILD_END, weather_time)
		rain_strength = 0.0
	elif weather_time < RAIN_END:
		cloud_amount = 1.0
		rain_strength = smoothstep(CLOUD_BUILD_END, CLOUD_BUILD_END + 6.0, weather_time)
		rain_strength *= 1.0 - smoothstep(RAIN_END - 7.0, RAIN_END, weather_time)
	else:
		cloud_amount = 1.0 - smoothstep(RAIN_END, CYCLE_SECONDS, weather_time)
		rain_strength = 0.0

func _choose_rain_cell(refill: bool) -> void:
	var angle := rng.randf() * TAU
	var radius := sqrt(rng.randf()) * 54.0
	rain_center = Vector2(cos(angle), sin(angle)) * radius
	cloud_height = clampf(Dome.roof_height(rain_center.length()) - 5.5, 34.0, 82.0)
	if refill:
		for i in DROP_COUNT:
			drops[i].active = false

func _build_rain() -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.60, 0.80, 1.0, 0.92)
	material.emission_enabled = true
	material.emission = Color(0.18, 0.32, 0.48)
	material.emission_energy_multiplier = 0.35
	var streak := CylinderMesh.new()
	streak.top_radius = 0.014
	streak.bottom_radius = 0.020
	streak.height = 1.0
	streak.radial_segments = 4
	streak.rings = 1
	streak.material = material
	drop_meshes = MultiMesh.new()
	drop_meshes.transform_format = MultiMesh.TRANSFORM_3D
	drop_meshes.mesh = streak
	drop_meshes.instance_count = DROP_COUNT
	var node := MultiMeshInstance3D.new()
	node.name = "RainDrops"
	node.multimesh = drop_meshes
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 180.0
	add_child(node)
	for i in DROP_COUNT:
		drops.append({"position": Vector3.ZERO, "velocity": Vector3.ZERO, "active": false, "bounces": 0})
		_hide_drop(i)

func _update_drops(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in DROP_COUNT:
		var drop: Dictionary = drops[i]
		if not drop.active:
			if rain_strength > 0.02 and rng.randf() < rain_strength * delta * 1.8:
				_spawn_drop(drop, rain_strength > 0.7 and rng.randf() < 0.18)
			else:
				_hide_drop(i)
			continue
		var previous: Vector3 = drop.position
		drop.velocity.y -= GRAVITY * delta
		var next: Vector3 = previous + drop.velocity * delta
		var query := PhysicsRayQueryParameters3D.create(to_global(previous), to_global(next))
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			drop.position = to_local(hit.position + normal * 0.025)
			if drop.bounces == 0 and drop.velocity.dot(normal) < 0.0:
				# A wet, low-energy rebound with a lateral splash. Gravity takes over
				# immediately, so roof pitch and lunar gravity shape the trajectory.
				drop.velocity = drop.velocity.bounce(normal) * rng.randf_range(0.18, 0.30)
				drop.velocity += Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.15, 0.65), rng.randf_range(-1.0, 1.0))
				drop.bounces = 1
				bounce_count += 1
			else:
				drop.active = false
		else:
			drop.position = next
			if drop.position.y < -3.0 or drop.position.length() > 160.0:
				drop.active = false
		drops[i] = drop
		if drop.active:
			_draw_drop(i, drop.position, drop.velocity)
		else:
			_hide_drop(i)

func _spawn_drop(drop: Dictionary, fill_column: bool) -> void:
	var angle := rng.randf() * TAU
	var radius := sqrt(rng.randf()) * LOCAL_RAIN_RADIUS
	var y := rng.randf_range(5.0, cloud_height - 2.0) if fill_column else cloud_height - rng.randf_range(1.0, 3.0)
	drop.position = Vector3(rain_center.x + cos(angle) * radius, y, rain_center.y + sin(angle) * radius)
	drop.velocity = Vector3(rng.randf_range(-0.32, 0.32), -rng.randf_range(2.0, 4.0), rng.randf_range(-0.32, 0.32))
	drop.bounces = 0
	drop.active = true

func _draw_drop(index: int, position: Vector3, velocity: Vector3) -> void:
	var direction := velocity.normalized()
	var helper := Vector3.RIGHT if absf(direction.dot(Vector3.RIGHT)) < 0.92 else Vector3.FORWARD
	var x := helper.cross(direction).normalized()
	var z := x.cross(direction).normalized()
	var length := clampf(velocity.length() * 0.05, 0.16, 0.72)
	drop_meshes.set_instance_transform(index, Transform3D(Basis(x, direction * length, z), position))

func _hide_drop(index: int) -> void:
	drop_meshes.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
