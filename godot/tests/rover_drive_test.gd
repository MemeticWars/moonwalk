extends SceneTree

class FlatTerrain extends Node3D:
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func has_ground(_point: Vector3) -> bool:
		return true

class FakeRoads extends Node:
	var descriptors_by_tile: Dictionary = {
		Vector2i.ZERO: [{"a": Vector3(-100, 0, 0), "b": Vector3(100, 0, 0)}]
	}

class FakeGame extends Node:
	var roads: Node

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var terrain := FlatTerrain.new()
	root.add_child(terrain)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500, 1, 500)
	collider.shape = box
	body.position.y = -0.5
	body.add_child(collider)
	root.add_child(body)
	var rover := preload("res://scripts/lunar_lorry.gd").new()
	rover.terrain = terrain
	rover.controlled = true
	rover.set_patrol_route(PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -20)]))
	root.add_child(rover)
	var truck := preload("res://scripts/lunar_truck.gd").new()
	truck.terrain = terrain
	truck.controlled = true
	truck.set_patrol_route(PackedVector3Array([Vector3(12, 0, 0), Vector3(12, 0, 0), Vector3(12, 0, -20)]))
	root.add_child(truck)
	await create_timer(4).timeout
	assert(rover.rig_ready and truck.rig_ready)
	assert(rover.vwheels.size() == 4 and truck.vwheels.size() == 8)
	assert(is_equal_approx(rover.drive_speed_limit() * 3.6, 28.8), "Normal rover speed limit must remain 28.8 km/h")
	rover.drive_boost = true
	assert(is_equal_approx(rover.drive_speed_limit() * 3.6, 40.0), "Shift boost must raise rover limit to 40 km/h")
	rover.drive_boost = false
	var start := rover.position
	var truck_start := truck.position
	rover.drive_brake = false
	rover.drive_throttle = 1
	truck.drive_brake = false
	truck.drive_throttle = 1
	await create_timer(8).timeout
	print("DRIVE delta=", rover.position - start, " truck=", truck.position - truck_start, " speed=", rover.linear_velocity)
	assert(rover.position.z < start.z - 2, "W must drive toward the model's front (-Z)")
	assert(truck.position.z < truck_start.z - 2, "Cargo drone must move on its eight physical wheels")
	var speed := rover.linear_velocity.length()
	rover.drive_throttle = 0
	await create_timer(1).timeout
	assert(rover.linear_velocity.length() > speed * 0.65, "Releasing throttle must preserve momentum")
	rover.drive_brake = true
	await create_timer(8).timeout
	assert(rover.linear_velocity.length() < 0.5, "Brakes must bring rover to a stop")
	truck.global_transform = Transform3D(Basis.IDENTITY, rover.position + Vector3(0, 0, 40))
	truck.linear_velocity = Vector3.ZERO
	truck.angular_velocity = Vector3.ZERO
	var follower := preload("res://scripts/rover_convoy.gd").new()
	follower.add_child(follower.camera)
	follower.add_child(follower.label)
	follower.rover = rover
	follower.trucks.append(truck)
	follower.paths.append([])
	follower.last_leader.append(rover.position)
	var fake_game := FakeGame.new()
	fake_game.roads = FakeRoads.new()
	follower.game = fake_game
	var axis := follower._nearest_road_axis(Vector3(8, 0, 6))
	assert(not axis.is_empty() and absf(axis.point.z) < 0.001 and absf(axis.tangent.x) > 0.99,
		"Road autopilot must project the rover onto the nearest road axis")
	var follow_start := truck.position
	rover.drive_brake = false
	rover.drive_throttle = 0.65
	rover.drive_steer = 0.25
	for i in 480:
		await physics_frame
		follower._follow(0, false)
	print("FOLLOW delta=", truck.position - follow_start, " gap=", truck.position.distance_to(rover.position))
	assert(truck.position.distance_to(follow_start) > 2, "Drone must follow under engine power")
	assert(truck.position.distance_to(rover.position) > 20, "Large drone must preserve its stopping gap")
	follower.free()
	rover.drive_brake = true
	rover.drive_throttle = 0
	# An airborne vehicle has no artificial drag or upright torque.
	rover.position = Vector3(0, 30, 0)
	rover.linear_velocity = Vector3(3, 0, 0)
	await create_timer(1).timeout
	assert(absf(rover.linear_velocity.y + 1.62) < 0.15, "Lunar ballistic acceleration must be 1.62 m/s2")
	assert(absf(rover.linear_velocity.x - 3) < 0.1, "Vacuum must not slow horizontal flight")
	print("ROVER DRIVE PASS: rigs, forward drive, coasting, brakes, lunar ballistics")
	quit()
