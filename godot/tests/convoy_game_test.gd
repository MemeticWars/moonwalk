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
	var port := game.surface.get_node("TychoCity/CityPaths/TychoCosmoport")
	var stands: PackedVector3Array = port.truck_stands_global()
	assert(stands.size() == 2, "Tycho must provide two freight parking stands outside the airlock")
	for truck in convoy.trucks:
		assert(truck.rig_ready and truck.vwheels.size() == 4)
		assert(is_equal_approx(truck.mass, 28800.0), "Scaled freight truck mass must match its 12 m hull")
	var truck_size: Vector3 = convoy.trucks[0]._combined_aabb(convoy.trucks[0]._all_meshes(convoy.trucks[0].model)).size
	var truck_length: float = maxf(maxf(truck_size.x, truck_size.y), truck_size.z)
	assert(truck_length > 11.5, "Freight trucks must be twice the original 6 m size")
	for i in convoy.trucks.size():
		assert(convoy.trucks[i].global_position.distance_to(stands[i]) < 2.0, "Truck must spawn on its marked parking stand")
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
	print("CONVOY GAME PASS: two four-wheel freight drones, boarding, player follows vehicle, pause, moving-exit guard")
	quit()
