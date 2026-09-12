extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := (load("res://scenes/moonwalk.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(5).timeout
	var actor: CharacterBody3D = world.theia
	assert(actor.character_name == "Agnes" and actor.players.size() == 6)
	actor.enabled = false
	actor.set_camera_mode(1)
	actor.yaw = PI + 0.4
	actor.distance = 3.4
	actor.orbit_length = -1.0
	actor._update_camera()
	world.lunar_sky.suspended = true
	for i in 6:
		for j in 6:
			actor.visuals[j].visible = i == j
			actor.players[j].speed_scale = 0.0
		var player: AnimationPlayer = actor.players[i]
		player.seek(player.current_animation_length * 0.3, true)
		assert(player.current_animation_length > 0.5)
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		var label: String = ["walk", "run", "left", "right", "idle", "jump"][i]
		root.get_texture().get_image().save_png("res://../artifacts/agnes_%s.png" % label)
		print("AGNES: ", label, " / ", player.current_animation, " / ", player.current_animation_length, "s")
	print("AGNES PREVIEW PASS: all six suit clips rendered")
	quit()
