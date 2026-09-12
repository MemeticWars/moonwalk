extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := preload("res://scripts/lunar_terrain.gd").new()
	terrain.colony = {"name": "Test", "latitude": 0.0, "longitude": 0.0}
	root.add_child(terrain)
	var actor := preload("res://scripts/agnes.gd").new()
	actor.terrain = terrain
	root.add_child(actor)
	await process_frame
	var collision := actor.get_child(0) as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D
	var visual_height := actor._visual_mesh_bounds(actor.visuals[0], actor.pivot.transform).size.y
	print("AGNES HEIGHT PROBE: visual=%.4f m pivot=%.6f helmet_basis=%.6f" % [visual_height, actor.pivot.scale.x, actor.helmets[0].global_basis.x.length()])
	assert(absf(visual_height - 1.8) < 0.01, "All Agnes suit clips must share the 1.8 m reference scale")
	assert(actor.visuals.size() == 6 and actor.players.size() == 6, "All six Agnes animations must remain available")
	for visual in actor.visuals:
		assert(visual.get_parent() == actor.pivot, "Every Agnes animation must inherit the common 1.8 m suit scale")
	assert(is_equal_approx(capsule.height, 1.8) and is_equal_approx(capsule.radius, 0.27), "Collision must match 1.8 m Agnes")
	print("AGNES HEIGHT TEST: visual=%.4f m capsule=%.2f m helmet_basis=%.6f" % [visual_height, capsule.height, actor.helmets[0].global_basis.x.length()])
	quit()
