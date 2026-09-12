extends SceneTree

class FlatTerrain extends Node3D:
	func height_at(_x: float, _z: float) -> float: return 0.0
	func has_ground(_point: Vector3) -> bool: return true
	func update_focus(_point: Vector3) -> void: pass

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := FlatTerrain.new()
	world.add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	collider.shape = box
	collider.position.y = -0.5
	floor_body.add_child(collider)
	world.add_child(floor_body)
	for script in [preload("res://scripts/agnes.gd"), preload("res://scripts/human_controller.gd")]:
		var actor: CharacterBody3D = script.new()
		# human_controller.gd defaults to no humanoid_model_path (plain shared
		# clips, like Agnes). Point this instance at an unrelated skinned model
		# with no animations of its own, to prove the generalized mechanics
		# still work on any rigged humanoid, not just Agnes.
		if script != preload("res://scripts/agnes.gd"):
			actor.humanoid_model_path = "res://assets/theia/theia_hooded_walking.glb"
		actor.terrain = ground
		world.add_child(actor)
		actor.set_physics_process(false)
		assert(actor.players.size() == 10, "Both humans must load all shared motions")
		actor.global_position = Vector3(0, 0.04, 0)
		actor.climb_forward = Vector3.BACK
		actor.climb_auto_walk = true
		actor.climb_auto_walk_target = actor.global_position
		actor._show_climb(actor.CRAWL, 0.2)
		var stand: Animation = actor.players[actor.STAND_UP].get_animation(actor.players[actor.STAND_UP].current_animation)
		assert(stand.loop_mode == Animation.LOOP_NONE)
		var hip_rise := 0.0
		for track in stand.get_track_count():
			if stand.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
			var start: Vector3 = stand.track_get_key_value(track, 0)
			for key in stand.track_get_key_count(track):
				var value: Vector3 = stand.track_get_key_value(track, key)
				assert(is_equal_approx(value.x, start.x) and is_equal_approx(value.z, start.z), "Stand animation must not move the body across the roof")
				hip_rise = maxf(hip_rise, absf(value.y - start.y))
		assert(hip_rise > 0.05, "Standing must retain vertical hip motion")
		var rig: Skeleton3D = actor.MOTIONS.skeleton_in(actor.visuals[actor.CRAWL])
		print("ACTOR POSE ", actor.character_name, " scale ", actor.pivot.scale, " foot ", rig.global_transform * rig.get_bone_global_pose(rig.find_bone("LeftFoot")).origin)
		var saw_stand := false
		for tick in 600:
			await physics_frame
			if actor.climb_auto_walk:
				actor._physics_climb_auto_advance(1.0 / 60.0)
			elif actor.stand_up_active:
				saw_stand = true
				assert(actor.active_visual == actor.STAND_UP)
				actor._physics_stand_up(1.0 / 60.0)
			else: break
		print("STAND STATE ", actor.character_name, " ", actor.stand_up_elapsed, " length ", stand.length, " active ", actor.active_visual, " pos ", actor.global_position)
		assert(saw_stand and not actor.stand_up_active and not actor.climb_auto_walk, "Crawl -> Stand_Up2 -> idle must complete")
		actor.set_physics_process(true)
		await create_timer(0.7).timeout
		assert(actor.is_on_floor() and actor.global_position.y > -0.1, "Both humans remain supported after standing")
		print("HUMAN ACTOR PASS: ", actor.character_name, " loads 10 motions and completes supported Crawl -> Stand_Up2 -> idle")
		actor.queue_free()
		await process_frame
	quit()
