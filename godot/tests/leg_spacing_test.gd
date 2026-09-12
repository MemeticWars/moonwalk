extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _hip_gap(actor: CharacterBody3D, visual: Node3D) -> float:
	var skeleton := visual.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var left := skeleton.find_bone("LeftUpLeg")
	var right := skeleton.find_bone("RightUpLeg")
	return (skeleton.global_transform * skeleton.get_bone_global_pose(left).origin).distance_to(skeleton.global_transform * skeleton.get_bone_global_pose(right).origin)

func _foot_gap(visual: Node3D) -> float:
	var skeleton := visual.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var left := skeleton.find_bone("LeftFoot")
	var right := skeleton.find_bone("RightFoot")
	return (skeleton.global_transform * skeleton.get_bone_global_pose(left).origin).distance_to(skeleton.global_transform * skeleton.get_bone_global_pose(right).origin)

func _run() -> void:
	var world := (load("res://scenes/moonwalk.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(4).timeout
	var actor: CharacterBody3D = world.theia
	actor.enabled = false
	for player in actor.players: player.speed_scale = 0
	var walk_gap := 0.0
	var run_gap := 0.0
	var walk_foot_gap := INF
	var run_foot_gap := INF
	for phase in [0.0, 0.25, 0.5, 0.75]:
		actor.players[0].seek(actor.players[0].current_animation_length * phase, true)
		actor.players[1].seek(actor.players[1].current_animation_length * phase, true)
		await process_frame
		await process_frame
		walk_gap = maxf(walk_gap, _hip_gap(actor, actor.visuals[0]))
		run_gap = maxf(run_gap, _hip_gap(actor, actor.visuals[1]))
		walk_foot_gap = minf(walk_foot_gap, _foot_gap(actor.visuals[0]))
		run_foot_gap = minf(run_foot_gap, _foot_gap(actor.visuals[1]))
	assert(walk_gap > 0.20, "Walk thighs must have a clear physical gap")
	assert(walk_gap > run_gap, "Walk should be wider than the original run rest spacing")
	print("LEG SPACING: thighs max walk=", walk_gap, " m, run=", run_gap, " m; feet minimum walk=", walk_foot_gap, " m, run=", run_foot_gap, " m")
	assert(walk_foot_gap > 0.12, "Walk boots must never cross at their closest phase")
	for i in actor.visuals.size(): actor.visuals[i].visible = i == 0
	actor.set_camera_mode(1)
	actor.distance = 3.3
	actor.yaw = PI + 0.2
	actor._update_camera()
	actor.players[0].seek(actor.players[0].current_animation_length * 0.5, true)
	await process_frame
	var previous_foot: String = actor.last_stamped_foot
	var expected_foot: Vector3 = actor._foot_position_for_stamp()
	actor.last_stamped_foot = previous_foot
	actor._stamp_foot()
	var stamped: Vector3 = actor.footprints.back().global_position
	assert(Vector2(stamped.x - expected_foot.x, stamped.z - expected_foot.z).length() < 0.001, "Footprint must use the animated foot position")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../artifacts/agnes_walk_wide_legs.png")
	print("LEG SPACING PASS")
	quit()
