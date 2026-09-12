extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 0.2, 200.0)
	collision.shape = shape
	collision.position.y = -0.1
	floor.add_child(collision)
	root.add_child(floor)
	var weather := preload("res://scripts/tycho_weather.gd").new()
	root.add_child(weather)
	weather.weather_time = 22.0
	for i in weather.DROP_COUNT:
		var drop: Dictionary = weather.drops[i]
		drop.position = Vector3(float(i % 10) - 5.0, 1.2 + float(i % 4) * 0.15, float(i / 10) - 5.0)
		drop.velocity = Vector3(0.0, -3.0, 0.0)
		drop.active = true
		drop.bounces = 0
		weather.drops[i] = drop
	for frame in 120:
		await physics_frame
	check(weather.bounce_count > 0, "Rain drops must rebound from real collision surfaces")
	check(is_equal_approx(weather.GRAVITY, float(ProjectSettings.get_setting("physics/3d/default_gravity"))),
		"Rain must use the project's lunar gravity")
	print("TYCHO WEATHER TEST: %d failures; %d roof/ground bounces" % [failures, weather.bounce_count])
	quit(1 if failures else 0)
