extends SceneTree
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/moonwalk.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._toggle_map()
	game.globe.pitch = deg_to_rad(-43.66)
	game.globe.yaw = deg_to_rad(-11.3)
	game.globe.set_process(false)
	game.globe.distance = 2.15
	game.globe._update_camera()
	for i in game.globe.moon_lods.size(): game.globe.moon_lods[i].visible = i == 0
	for frame in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/orbit_shadow_coarse.png")
	game.globe.set_process(true)
	game.globe.distance = 1.04
	game.globe._process(0.0)
	var heights := [50000.0,10000.0,3000.0,800.0]
	var index := 0
	var deadline := Time.get_ticks_msec()+180000
	while game.landing_busy and Time.get_ticks_msec()<deadline:
		await process_frame
		var eye: Vector3 = root.get_camera_3d().global_position
		if index < heights.size() and game.globe.approach and eye.y < heights[index]:
			if heights[index] >= 3000.0:
				assert(game.globe.meso.detail_blend == 0.0, "Survey detail must not appear in the broad meso view")
				assert(not game.terrain.visible, "Walking tiles must not form a sharp central square")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../artifacts/meso_%dm.png" % heights[index])
			print("CAPTURE ",heights[index]," eye=",eye," patches=",game.globe.meso.patches.size()," detail=",game.globe.meso.detail_blend)
			index += 1
	if game.landing_busy:
		push_error("Approach timed out")
		quit(1)
		return
	assert(game.terrain.visible and game.terrain.material.get_shader_parameter("detail_blend") == 1.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/meso_landed.png")
	print("MESO VISUAL PASS; slowest mesh job ms=", game.globe.meso.max_patch_usec/1000.0)
	quit()
