extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/agnes_jump_%s.png" % label)

func _run() -> void:
	var world := (load("res://scenes/moonwalk.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(4).timeout
	var actor: CharacterBody3D = world.theia
	actor.set_control_scheme(true)
	actor.set_camera_mode(1)
	actor.yaw = PI + 0.4
	actor.distance = 4.4
	actor.orbit_length = -1.0
	var clip: Animation = actor.players[5].get_animation(actor.players[5].current_animation)
	var hips_found := false
	for track in clip.get_track_count():
		if clip.track_get_type(track) == Animation.TYPE_POSITION_3D and String(clip.track_get_path(track)).ends_with(":Hips"):
			hips_found = true
			for key in clip.track_get_key_count(track):
				assert(clip.track_get_key_value(track, key).is_equal_approx(clip.track_get_key_value(track, 0)), "Baked vault translation must be removed")
	assert(hips_found, "Jump hips track must be identified")
	var origin := actor.position
	actor._try_jump()
	await create_timer(0.5).timeout
	assert(actor.jump_active and actor.active_visual == 5 and not actor.is_on_floor())
	assert(actor.position.y > origin.y + 0.8)
	var vertical_speed: float = actor.velocity.y
	actor._try_jump()
	assert(actor.velocity.y == vertical_speed, "No second jump in midair")
	await capture("rise")
	actor.set_paused(true)
	var pose: float = actor.players[5].current_animation_position
	var paused_position := actor.position
	await create_timer(0.2).timeout
	assert(actor.position == paused_position and actor.players[5].current_animation_position == pose)
	actor.set_paused(false)
	await create_timer(1.1).timeout
	assert(actor.jump_phase > 0.38 and actor.jump_phase < 0.48)
	await capture("apex")
	actor.toggle_free_camera()
	await create_timer(2.2).timeout
	assert(actor.is_on_floor() and not actor.jump_active, "Jump must land even while the camera is free")
	assert(Vector2(actor.position.x - origin.x, actor.position.z - origin.z).length() < 0.05, "Animation must not push the collision body forward")
	assert(actor.active_visual == 4, "Return to idle after landing")
	actor.toggle_free_camera()
	await create_timer(0.1).timeout
	await capture("landed")
	print("JUMP PASS: root motion removed, slowed airborne pose, no double jump, pause, free-camera landing, idle recovery")
	quit()
