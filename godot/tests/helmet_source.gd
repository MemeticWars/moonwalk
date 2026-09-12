extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var model := (load("res://assets/agnes/helmet.glb") as PackedScene).instantiate()
	scene.add_child(model)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -30, 0)
	scene.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	scene.add_child(env)
	var camera := Camera3D.new()
	camera.fov = 40
	scene.add_child(camera)
	for i in 4:
		camera.position = Vector3(sin(i * PI / 2.0), 0.15, cos(i * PI / 2.0)) * 3.8
		camera.look_at(Vector3.ZERO)
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../artifacts/helmet_source_%d.png" % i)
	quit()
