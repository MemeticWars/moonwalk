extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _compute_box(fox: Node3D) -> AABB:
	var box := AABB()
	var seeded := false
	for m: MeshInstance3D in fox.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		box = b if not seeded else box.merge(b)
		seeded = true
	return box

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.06, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.35, 0.38)
	environment.ambient_light_energy = 1.0
	env.environment = environment
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.6
	world.add_child(sun)

	var fox := (load("res://assets/colonies/tycho/modules/foxy_model_Animation_Walking_withSkin.glb") as PackedScene).instantiate() as Node3D
	world.add_child(fox)

	var raw_box := _compute_box(fox)
	print("RAW BOX pos=", raw_box.position, " size=", raw_box.size)
	var scale := 0.55 / maxf(raw_box.size.length(), 0.0001)
	fox.scale = Vector3.ONE * scale

	# The bind-pose AABB is a sub-millimetre sliver offset from the local
	# origin; scaling the model up by ~1e5-1e6x amplifies that tiny offset
	# into a multi-metre world-space displacement. Recompute the box AFTER
	# scaling and frame the camera on ITS centre, not a fixed point.
	await process_frame
	var scaled_box := _compute_box(fox)
	print("SCALED BOX pos=", scaled_box.position, " size=", scaled_box.size)
	var center: Vector3 = scaled_box.position + scaled_box.size * 0.5
	var radius: float = maxf(scaled_box.size.length(), 0.2)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = center + Vector3(radius, radius * 0.65, radius)
	cam.look_at(center)
	cam.current = true

	await create_timer(1.0).timeout
	for m: MeshInstance3D in fox.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		print("MESH ", m.name, " global_pos=", m.global_transform.origin, " visible=", m.visible)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/fox_preview2.png")
	print("DONE")
	quit()
