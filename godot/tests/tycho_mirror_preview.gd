extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.14, 0.17)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -20, 0)
	sun.light_energy = 1.3
	scene.add_child(sun)
	for mirrored in [false, true]:
		var path := "res://assets/colonies/tycho/modules/l-shape-building%s.glb" % ("-mirrored" if mirrored else "")
		var model := (load(path) as PackedScene).instantiate() as Node3D
		model.position.x = 16 if mirrored else -16
		scene.add_child(model)
		assert(model.transform.basis.determinant() > 0.0)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 67
	camera.position = Vector3(12, 42, 60)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 4, 0))
	camera.make_current()
	await create_timer(2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/tycho_l_mirror_front.png")
	camera.position = Vector3(-12, 42, -60)
	camera.look_at(Vector3(0, 4, 0))
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/tycho_l_mirror_back.png")
	print("MIRROR PREVIEW PASS")
	quit()
