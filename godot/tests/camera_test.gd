extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := (load("res://scenes/moonwalk.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(6).timeout
	world.lunar_sky.suspended = true
	world.lunar_sky.apply_phase(0.06)
	var actor: CharacterBody3D = world.theia
	actor.persist_settings = false
	actor.set_control_scheme(true)
	for mesh in actor.visuals[0].find_children("*", "MeshInstance3D", true, false):
		var mat: StandardMaterial3D = mesh.get_active_material(0)
		assert(not mat.emission_enabled and not mat.disable_receive_shadows, "Theia must respond to scene lighting and shadows")
	var origin := actor.global_position
	var max_body_drift := 0.0
	var max_camera_step := 0.0
	var previous_eye: Vector3 = actor.camera.global_position
	var prefix := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	for mode in [1, 0]:
		actor.set_camera_mode(mode)
		for step in 180:
			actor.yaw = step * TAU / 180.0
			await physics_frame
			await process_frame
			max_body_drift = maxf(max_body_drift, origin.distance_to(actor.global_position))
			if step > 0:
				max_camera_step = maxf(max_camera_step, previous_eye.distance_to(actor.camera.global_position))
			previous_eye = actor.camera.global_position
			if step % 45 == 0 and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://../artifacts/orbit_%s_%d_%d.png" % [prefix, mode, step])
	print("ORBIT: body drift=", max_body_drift, "m; largest camera step=", max_camera_step, "m")
	assert(max_body_drift < 0.005, "Orbiting must not displace the character")
	actor.set_camera_mode(1)
	actor.yaw = 0.0
	actor.pitch = 0.0
	actor._update_camera()
	var target: Vector3 = actor.global_position + Vector3.UP * actor.target_height
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.2)
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.global_position = target + Vector3.BACK * 2.0
	await create_timer(0.1).timeout
	var close_length: float = actor.camera.global_position.distance_to(target)
	assert(close_length < 1.9, "Camera must retract before the obstacle")
	assert(absf(actor.camera.global_position.x - target.x) < 0.001, "Collision must not deflect camera sideways")
	obstacle.queue_free()
	await create_timer(0.15).timeout
	var return_length: float = actor.camera.global_position.distance_to(target)
	assert(return_length > close_length and return_length < close_length + 0.8, "Camera must return gradually after an obstruction")
	await create_timer(1.5).timeout
	assert(absf(actor.camera.global_position.distance_to(target) - actor.distance) < 0.01, "Camera must recover the selected orbit distance")
	print("CAMERA PASS: two stationary orbits, obstacle retraction, smooth recovery")
	quit()
