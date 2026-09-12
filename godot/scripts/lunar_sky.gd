extends Node

# Deliberately accelerated visual cycle, not an astronomical ephemeris.
@export var cycle_seconds := 180.0
@export var phase := 0.06
@export var speed_multiplier := 1.0
@export var earth_diameter_degrees := 4.0
@export var sun_diameter_degrees := 0.8
var suspended := false
var environment: Environment
var sun: DirectionalLight3D
var material := ShaderMaterial.new()
var earth_direction := Vector3.FORWARD
var sun_direction := Vector3.FORWARD
var sun_override_direction := Vector3.ZERO
var earth_altitude_degrees := 0.0

func initialize(env: Environment, light: DirectionalLight3D) -> void:
	environment = env
	sun = light
	material.shader = load("res://shaders/lunar_sky.gdshader")
	preload("res://scripts/bright_stars.gd").configure(material)
	material.set_shader_parameter("earth_map", load("res://assets/moon/earth_blue_marble.png"))
	material.set_shader_parameter("earth_radius", deg_to_rad(earth_diameter_degrees * 0.5))
	material.set_shader_parameter("sun_radius", deg_to_rad(sun_diameter_degrees * 0.5))
	var sky := Sky.new()
	sky.sky_material = material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	# Realtime-mode skies are always rendered at radiance size 256 regardless of
	# what's requested here; set it explicitly to match so Godot doesn't warn
	# and silently override a different value every time the sky initializes.
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	apply_phase(phase)

func direction(azimuth: float, altitude: float) -> Vector3:
	var az := deg_to_rad(azimuth)
	var alt := deg_to_rad(altitude)
	return Vector3(sin(az) * cos(alt), sin(alt), -cos(az) * cos(alt)).normalized()

func apply_phase(value: float) -> void:
	phase = fposmod(value, 1.0)
	var angle := phase * TAU
	earth_altitude_degrees = 1.0 + 10.0 * sin(angle)
	earth_direction = direction(-15.0 + 3.0 * sin(angle * 2.0), earth_altitude_degrees)
	# The Sun stays above the horizon in this local exploration slice.
	# Earth animation must not make the ground shadows crawl during camera inspection.
	sun_direction = sun_override_direction.normalized() if sun_override_direction.length_squared() > 0.5 else direction(12.0, 3.0)
	material.set_shader_parameter("earth_direction", earth_direction)
	material.set_shader_parameter("sun_direction", sun_direction)
	material.set_shader_parameter("earth_rotation", 0.025 + phase)
	sun.look_at_from_position(Vector3.ZERO, -sun_direction, Vector3.UP)

func set_surface_view(value: bool) -> void:
	material.set_shader_parameter("show_bodies", value)

func _process(delta: float) -> void:
	if not suspended and material.shader != null and speed_multiplier > 0:
		apply_phase(phase + delta * speed_multiplier / maxf(cycle_seconds, 1.0))
