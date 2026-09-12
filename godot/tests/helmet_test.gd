extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var world := (load("res://scenes/moonwalk.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(5).timeout
	var actor: CharacterBody3D = world.theia
	assert(actor.helmets.size() == 6)
	assert(is_equal_approx(actor.reference_height_m, 1.8), "Agnes suit must use a 1.8 m reference height")
	var capsule := actor.get_child(0) as CollisionShape3D
	assert(capsule.shape is CapsuleShape3D and is_equal_approx(capsule.shape.height, 1.8) and is_equal_approx(capsule.shape.radius, 0.27), "Agnes collision capsule must follow her 1.8 m proportions")
	actor.set_camera_mode(4)
	actor.enabled = false
	world.lunar_sky.suspended = true
	for player in actor.players: player.speed_scale = 0
	for i in 6:
		actor.players[i].seek(actor.players[i].current_animation_length * 0.3, true)
		for j in 6: actor.visuals[j].visible = i == j
		await create_timer(0.1).timeout
		var helmet: Node3D = actor.helmets[i]
		var skeleton := actor.visuals[i].find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var head: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
		assert(helmet.global_position.distance_to(head) < 0.25, "Helmet must follow the animated head")
		assert(absf(helmet.global_basis.x.length() - 0.1695) < 0.002, "Helmet must retain Agnes's 1.8 m complete-suit scale across clips")
		if DisplayServer.get_name() != "headless":
			actor.camera.global_position = helmet.global_position + Vector3(0.28, 0.1, -1.0)
			actor.camera.look_at(helmet.global_position)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../artifacts/helmet_clip_%d.png" % i)
	for shaded in [false, true]:
		actor.set_visor_shade(shaded)
		actor.visor_shade_amount = 1.0 if shaded else 0.0
		actor._apply_visor_shade()
		for helmet in actor.helmets: assert(is_equal_approx(helmet.visor_material.get_shader_parameter("shade"), actor.visor_shade_amount))
		if DisplayServer.get_name() != "headless":
			await create_timer(0.1).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../artifacts/helmet_%s.png" % ("shaded" if shaded else "clear"))
	actor.set_camera_mode(3)
	assert(not actor.pivot.visible, "First person must not look through the head accessory")
	actor.enabled = true
	actor.set_visor_shade(true)
	assert(actor.visor_filter.visible, "Shaded visor must filter the first-person view")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../artifacts/helmet_fpp_shaded.png")
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_H
	toggle.pressed = true
	actor._unhandled_input(toggle)
	assert(not actor.visor_shade, "H must switch the visor target back to clear glass")
	actor.set_paused(true)
	actor._unhandled_input(toggle)
	assert(not actor.visor_shade, "Pause must block gameplay visor input")
	actor.set_paused(false)
	actor.set_visor_shade(true)
	world._toggle_map()
	await process_frame
	await process_frame
	assert(not actor.visor_filter.visible, "Visor tint must not cover the globe")
	print("HELMET PASS: six head attachments, stable scale, clear/shaded gradient switching, first-person visibility")
	quit()
