extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var world := (load("res://scenes/moonwalk.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(4).timeout
	var actor: CharacterBody3D = world.theia
	actor.set_camera_mode(4)
	actor.enabled = false
	for player in actor.players: player.speed_scale = 0
	for i in 6:
		var visual: Node3D = actor.visuals[i]
		var packs := visual.find_children("RigidBackpack*", "MeshInstance3D", true, false)
		assert(packs.size() == 1, "Exactly one rigid backpack per animation")
		var pack := packs[0] as MeshInstance3D
		assert(pack.skin == null, "Backpack must not be skinned")
		assert(pack.get_parent() is BoneAttachment3D, "Rigid backpack must attach to the torso")
		var attachment := pack.get_parent() as BoneAttachment3D
		assert(attachment.bone_name == "Spine02")
		var vertices: PackedVector3Array = pack.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var reference := -1.0
		for phase in [0.0, 0.2, 0.4, 0.6, 0.8]:
			actor.players[i].seek(actor.players[i].current_animation_length * phase, true)
			await process_frame
			await process_frame
			var span := (pack.global_transform * vertices[0]).distance_to(pack.global_transform * vertices[vertices.size() / 2])
			if reference < 0: reference = span
			assert(absf(span - reference) < 0.001, "Rigid backpack dimensions must not change during animation")
		for j in 6: actor.visuals[j].visible = i == j
		actor.players[i].seek(actor.players[i].current_animation_length * 0.3, true)
		if DisplayServer.get_name() != "headless":
			for side in [false, true]:
				actor.camera.global_position = actor.global_position + (Vector3(2.0, 1.45, 0.7) if side else Vector3(0.6, 1.6, 2.2))
				actor.camera.look_at(actor.global_position + Vector3(0, 1.2, 0))
				await create_timer(0.1).timeout
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://../artifacts/backpack_%d_%s.png" % [i, "side" if side else "back"])
	print("BACKPACK PASS: six unskinned torso attachments, constant dimensions across 30 poses")
	quit()
