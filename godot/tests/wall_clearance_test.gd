extends SceneTree

const Probe = preload("res://tests/crawl_roof_test.gd").ProbeAgnes
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 3
	body.position = at
	var shape := CollisionShape3D.new()
	var mesh := BoxShape3D.new()
	mesh.size = size
	shape.shape = mesh
	body.add_child(shape)
	root.add_child(body)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var actor := Probe.new()
	root.add_child(actor)
	box(Vector3(0, 2, 1), Vector3(6, 4, 0.4))
	# Upper storey projects 0.6 m over a full-width, solid lower facade.
	box(Vector3(10, 1, 1.6), Vector3(6, 2, 0.4))
	box(Vector3(10, 3, 1), Vector3(6, 2, 0.4))
	# Doorway with two jambs, lintel and a recessed interior wall.
	box(Vector3(18.8, 2, 1), Vector3(1.2, 4, 0.4))
	box(Vector3(21.2, 2, 1), Vector3(1.2, 4, 0.4))
	box(Vector3(20, 3, 1), Vector3(1.2, 2, 0.4))
	box(Vector3(20, 1, 1.6), Vector3(1.2, 2, 0.4))
	await physics_frame
	await physics_frame
	actor.global_position = Vector3(0, 0, 0.4)
	actor.velocity = Vector3.BACK
	actor._keep_wall_clearance()
	check(0.8 - actor.global_position.z >= actor.collision_radius_m + 0.5 - 0.01, "Walking leaves 0.5 m beyond the capsule")
	check(actor.velocity.z <= 0, "Walking into wall loses inward velocity")
	actor.visual_yaw = 0
	check(actor._try_start_climb(), "Q can reach the wall from the walking margin")
	check(actor.climb_approaching and not actor.climb_active, "Q approaches before climbing")
	actor.global_position.z = 0.4
	actor._keep_wall_clearance()
	check(is_equal_approx(actor.global_position.z, 0.4), "Approach bypasses walking margin")
	actor.climb_approaching = false
	actor.global_position = Vector3(10, 0, 0)
	check(not actor._doorway_ahead(Vector3.BACK), "Full-width overhang is not a doorway")
	check(not actor._nearest_climb_surface().is_zero_approx(), "Recessed solid facade remains climbable")
	actor.global_position = Vector3(20, 0, 0)
	check(actor._doorway_ahead(Vector3.BACK), "Recessed doorway is detected")
	check(actor._nearest_climb_surface().is_zero_approx(), "Q cannot redirect from doorway to its jamb")
	actor.global_position = Vector3(18.8, 0, 0)
	check(not actor._nearest_climb_surface().is_zero_approx(), "Solid wall beside door stays climbable")
	print("WALL CLEARANCE TEST: ", failures, " failures")
	quit(1 if failures else 0)
