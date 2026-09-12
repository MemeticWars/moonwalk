extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/moonwalk.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var actor: Node = game.theia
	Engine.time_scale = 10.0
	for target in [Vector2(12.5, 179.95), Vector2(-30.0, -179.95), Vector2(-43.66, -11.3)]:
		game._toggle_map()
		assert(game.map_mode)
		game._update_terrain_shadows()
		assert(game.lunar_sky.sun.shadow_enabled)
		assert(game.lunar_sky.sun.directional_shadow_max_distance < 10.0,"Orbital shadows must fit globe units")
		assert(game.globe.moon_lods[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)
		game.globe.pitch = deg_to_rad(target.x)
		game.globe.yaw = deg_to_rad(target.y)
		game.globe.distance = 1.04
		game.globe._process(0.0)
		assert(game.landing_busy, "Zoom must start descent at any longitude")
		var deadline := Time.get_ticks_msec() + 120000
		while game.landing_busy and Time.get_ticks_msec() < deadline:
			await process_frame
		assert(not game.landing_busy and not game.map_mode, "Descent must complete")
		assert(game.theia == actor, "Travel must preserve the actor and UI connections")
		assert(game.terrain.has_ground(game.theia.position), "Landing needs collision-ready terrain")
		assert(is_instance_valid(actor.footprint_root))
		if is_equal_approx(target.x, -43.66):
			assert(game.terrain.city_enabled, "Returning to Tycho must restore its surveyed city")
		else:
			assert(game.active_colony.get("wilderness", false))
			var ll: Vector2 = game.terrain.latlon_at(game.theia.position.x, game.theia.position.z)
			assert(ll.distance_to(target) < 0.001, "Landing must match selected coordinates")
		print("LANDED: ", game.active_colony_name)
	print("ORBITAL TRAVEL PASS: zoom departure, two wilderness destinations, dateline and return to Tycho")
	quit()
