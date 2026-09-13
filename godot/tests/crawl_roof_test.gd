extends SceneTree

class ProbeAgnes extends "res://scripts/human_controller.gd":
	func _init() -> void:
		reference_height_m = 1.8
		collision_radius_m = 0.27
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
		add_child(pivot)
		add_child(camera)
		for i in 10:
			var player := AnimationPlayer.new()
			var library := AnimationLibrary.new()
			library.add_animation("test", Animation.new())
			player.add_animation_library("", library)
			add_child(player)
			player.play("test")
			players.append(player)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = collision_radius_m
		capsule.height = reference_height_m
		shape.shape = capsule
		shape.position.y = reference_height_m * 0.5
		add_child(shape)
	func _show_climb(index: int, _time: float) -> void:
		active_visual = index
	func _update_camera() -> void:
		pass
	func _sync_visual(_moving: bool, _running: bool) -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func _box(at: Vector3, size: Vector3, tilt: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.position = at
	body.rotation.z = tilt
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)

func _run() -> void:
	var actor := ProbeAgnes.new()
	root.add_child(actor)
	_box(Vector3(0, -0.5, 0), Vector3(4, 1, 4))
	_box(Vector3(10, -0.5, 0), Vector3(4, 1, 4), deg_to_rad(35))
	_box(Vector3(20, -0.5, 0), Vector3(0.5, 1, 4))
	var dome := StaticBody3D.new()
	dome.collision_layer = 2
	dome.position = Vector3(30, -0.75, 0)
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.75
	collider.shape = sphere
	dome.add_child(collider)
	root.add_child(dome)
	await physics_frame
	await physics_frame
	assert(actor._roof_can_stand(Vector3.ZERO), "Wide flat roof supports standing")
	assert(not actor._roof_can_stand(Vector3(1.8, 0, 0)), "Edge must support the whole footprint")
	assert(not actor._roof_can_stand(Vector3(10, 0, 0)), "Sloping roof must not trigger standing")
	assert(not actor._roof_can_stand(Vector3(20, 0, 0)), "Narrow flat strip is insufficient")
	assert(not actor._roof_can_stand(Vector3(30, 0, 0)), "Horizontal dome apex alone is insufficient")
	assert(not actor._roof_can_stand(Vector3(40, 0, 0)), "Missing roof is not support")
	actor.climb_forward = Vector3.RIGHT
	assert(actor._roof_tangent_pitch(Vector3(-0.57, 0.82, 0)) < 0.0, "Roof rising toward Agnes gives a forward lean")
	assert(actor._roof_tangent_pitch(Vector3.UP) == 0.0, "Flat roof gives no artificial lean")
	actor.global_position = Vector3(0, -1.71, -1)
	actor.climb_forward = Vector3.BACK
	assert(not is_nan(actor._nearby_ledge_top()), "Flat roof still allows the ledge finish")
	actor.global_position = Vector3(30, -1.71, -0.88)
	assert(is_nan(actor._nearby_ledge_top()), "Dome must not enter the standing animation")
	var curve := StaticBody3D.new()
	curve.collision_layer = 2
	curve.position = Vector3(50, -4, 0)
	var curve_shape := CollisionShape3D.new()
	var curve_sphere := SphereShape3D.new()
	curve_sphere.radius = 4.0
	curve_shape.shape = curve_sphere
	curve.add_child(curve_shape)
	root.add_child(curve)
	_box(Vector3(52, -0.5, 0), Vector3(4, 1, 4))
	await physics_frame
	actor.global_position = Vector3(48, sqrt(12.0) - 4.0 + 0.04, 0)
	actor.climb_forward = Vector3.RIGHT
	actor.climb_auto_walk = true
	actor.climb_auto_walk_target = actor.global_position
	for tick in 360:
		await physics_frame
		actor._physics_climb_auto_advance(1.0 / 60.0)
		if not actor.climb_auto_walk: break
		assert(actor.active_visual == 8, "Curved roof must use crawl animation")
	assert(not actor.climb_auto_walk and actor.stand_up_active, "Crawl must enter Stand_Up2 on stable support")
	assert(actor.active_visual == actor.STAND_UP, "Stand_Up2 must be visible")
	var stand_position := actor.global_position
	for tick in 70:
		await physics_frame
		if actor.stand_up_active: actor._physics_stand_up(1.0 / 60.0)
	assert(not actor.stand_up_active and actor.global_position == stand_position, "Standing clip completes without body travel")
	assert(actor._roof_can_stand(actor.global_position), "Crawl ends only on a supported footprint")
	actor.global_position = Vector3(40, 0, 0)
	actor.climb_auto_walk = false
	actor.stand_up_active = true
	actor.climb_stand_started = true
	actor.stand_up_elapsed = 0.0
	for tick in 90:
		if actor.stand_up_active: actor._physics_stand_up(1.0 / 60.0)
	assert(not actor.stand_up_active and not actor.climb_auto_walk, "Failed Stand_Up2 never returns to crawl")
	actor.global_position = stand_position
	var landing_y := actor.global_position.y
	for tick in 120:
		await physics_frame
		actor.velocity.y -= 1.62 / 60.0
		actor.move_and_slide()
	assert(actor.is_on_floor() and actor.global_position.y > landing_y - 0.1, "Detailed roof supports normal physics after crawling")
	actor.set_collision_mask_value(2, false)
	actor.global_position = Vector3(20.2, 0.04, 0)
	actor.climb_auto_walk = true
	actor.climb_auto_walk_target = actor.global_position
	var edge_position := actor.global_position
	for tick in 30:
		await physics_frame
		actor._physics_climb_auto_advance(1.0 / 60.0)
	assert(actor.climb_auto_walk and actor.global_position.is_equal_approx(edge_position), "Missing next sample keeps Agnes crouched and stationary")
	print("CRAWL ROOF TEST PASS: flat roof, slope, edge, narrow strip, dome and missing support")
	quit()
