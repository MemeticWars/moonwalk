extends Node
## Volumetric cloud layer for the sealed Tycho habitat.
## SunshineClouds2 renders in the WorldEnvironment compositor, therefore clouds
## have real depth and are clipped by the dome and the rest of the city scene.

const CloudsDriver := preload("res://addons/SunshineClouds2/SunshineCloudsDriver.gd")

# Kept dynamically typed: the third-party driver exposes its controls through
# exported script properties, which are not part of Node's native API.
var driver
var clouds: CompositorEffect

func _exit_tree() -> void:
	# The compositor belongs to WorldEnvironment, which survives sector travel.
	# Detach the habitat's effect when its local city is unloaded.
	if clouds != null:
		for env: WorldEnvironment in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			if env.compositor != null:
				var effects := env.compositor.compositor_effects
				effects.erase(clouds)
				env.compositor.compositor_effects = effects
		# The driver's own exported reference (and this script's) otherwise
		# keep the compositor effect's RenderingDevice resources (pipelines,
		# shaders, buffers) alive until whatever engine teardown order happens
		# to drop the last reference -- as late as final RenderingDevice
		# shutdown, which reports them as leaked. Drop both here so the
		# CompositorEffect's refcount can hit zero, and its cleanup free the
		# RD resources, right when the habitat actually unloads.
		if driver != null:
			driver.clouds_resource = null
		clouds = null

func _ready() -> void:
	name = "TychoVolumetricClouds"
	driver = CloudsDriver.new()
	driver.name = "SunshineCloudsDriver"
	add_child(driver)
	call_deferred("_configure")

func _configure() -> void:
	# The standalone city-layout test deliberately has no render world. The game
	# always creates one before Tycho, while the test only needs the scene node.
	if get_tree().root.find_children("*", "WorldEnvironment", true, false).is_empty():
		set_meta("render_enabled", false)
		return
	driver.build_new_clouds()
	clouds = driver.clouds_resource
	if clouds == null:
		push_error("Tycho clouds could not create their compositor resource")
		return
	set_meta("render_enabled", true)
	# The dome crown is about 70 m above the city. A shallow cloud deck occupies
	# its upper third, leaving a visibly clear volume between streets and clouds.
	clouds.cloud_floor = 43.0
	clouds.cloud_ceiling = 66.0
	clouds.extra_large_noise_scale = 900.0
	clouds.large_noise_scale = 360.0
	clouds.medium_noise_scale = 145.0
	clouds.small_noise_scale = 48.0
	clouds.max_step_count = 112.0
	clouds.max_lighting_steps = 18.0
	clouds.resolution_scale = 2 # quarter resolution, temporally accumulated
	clouds.lod_bias = 0.85
	clouds.atmospheric_density = 0.025
	clouds.cloud_ambient_color = Color(0.72, 0.77, 0.84)
	clouds.cloud_ambient_tint = Color(0.70, 0.78, 0.88)
	clouds.clouds_anisotropy = 0.28
	clouds.clouds_powder = 0.38
	clouds.lighting_density = 0.72
	driver.wind_direction = Vector3(0.16, 0.0, -0.11)
	driver.extra_large_structures_wind_speed = 0.4
	driver.large_structures_wind_speed = 0.7
	driver.medium_structures_wind_speed = 1.0
	driver.small_structures_wind_speed = 1.3
	var directional_lights := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	var sun := directional_lights.front() as DirectionalLight3D if not directional_lights.is_empty() else null
	if sun != null:
		var tracked: Array[DirectionalLight3D] = [sun]
		var shadow_steps: Array[int] = [10]
		driver.tracked_directional_lights = tracked
		driver.tracked_directional_light_shadow_steps = shadow_steps
	driver.update_continuously = true
	driver.retrieve_texture_data()
	set_weather_amount(0.7)

func set_weather_amount(amount: float) -> void:
	if clouds == null:
		return
	var t := clampf(amount, 0.0, 1.0)
	# A real cloud field thins to almost nothing before rain, then gradually
	# fills the ceiling rather than popping in as a visible particle bank.
	clouds.clouds_coverage = lerpf(0.12, 0.67, t)
	clouds.clouds_density = lerpf(0.018, 0.42, t)
