extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game := preload("res://scripts/moonwalk.gd").new()
	root.add_child(game)
	var convoy: Node
	for child in game.surface.get_children():
		if child.get_script() == preload("res://scripts/rover_convoy.gd"):
			convoy = child
	assert(convoy != null, "Playable scene must contain the convoy controller")
	await create_timer(5).timeout
	assert(convoy.trucks.size() == 2)
	for truck in convoy.trucks:
		assert(truck.rig_ready and truck.vwheels.size() == 8)
	game.lorry.linear_velocity = Vector3.ZERO
	convoy._enter_rover()
	assert(convoy.driving and not game.theia.enabled and game.theia.collision_layer == 0)
	await physics_frame
	await physics_frame
	assert(game.theia.global_position.distance_to(game.lorry.global_position) < 1)
	game.theia.set_paused(true)
	await physics_frame
	await physics_frame
	assert(game.lorry.freeze, "Pause must suspend the vehicle")
	for truck in convoy.trucks:
		assert(truck.freeze)
	game.theia.set_paused(false)
	await physics_frame
	game.lorry.linear_velocity = Vector3(0, 0, -3)
	convoy._exit_rover()
	assert(convoy.driving, "Cannot exit a moving rover")
	game.lorry.linear_velocity = Vector3.ZERO
	convoy._exit_rover()
	assert(not convoy.driving and game.theia.enabled and game.theia.collision_layer != 0, "Stopped rover must allow a safe exit")
	print("CONVOY GAME PASS: two eight-wheel drones, boarding, player follows vehicle, pause, moving-exit guard")
	quit()
