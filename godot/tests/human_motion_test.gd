extends SceneTree

const Motions = preload("res://scripts/humanoid_motion_library.gd")
const Probe = preload("res://tests/crawl_roof_test.gd").ProbeAgnes

func _initialize() -> void:
	_run.call_deferred()

func _box(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.position = position
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)

func _run() -> void:
	var actor := Probe.new()
	root.add_child(actor)
	_box(Vector3(0, 1.5, 1), Vector3(5, 3, 0.1))
	# A door frame with a visible back wall must still be rejected.
	_box(Vector3(9, 1.5, 1), Vector3(0.5, 3, 0.1))
	_box(Vector3(11, 1.5, 1), Vector3(0.5, 3, 0.1))
	_box(Vector3(10, 2.6, 1), Vector3(2.5, 0.8, 0.1))
	_box(Vector3(10, 1.5, 1.6), Vector3(2.5, 3, 0.1))
	await physics_frame
	await physics_frame
	actor.visual_yaw = 0.0
	assert(actor._solid_climb_patch(Vector3.BACK, 1.7), "Full facade can be climbed")
	assert(actor._try_start_climb(), "Shared human controller starts on a solid wall")
	actor.climb_active = false
	actor.global_position.x = 10
	assert(actor._doorway_ahead(Vector3.BACK), "Detect opening under lintel despite the interior wall")
	assert(actor._nearest_climb_surface().is_zero_approx(), "Doorway must not redirect climbing to jambs")
	assert(not actor._try_start_climb(), "Q must not start climbing at a door")
	actor.climb_active = true
	actor.climb_forward = Vector3.BACK
	actor._physics_climb(1.0 / 60.0)
	assert(not actor.climb_active, "Door opening also blocks continued climbing")
	# Remove all target animations and rename the rig before borrowing motions.
	var target := (load("res://assets/agnes/fitted/agnes_suit_Animation_Idle_5_withSkin.glb") as PackedScene).instantiate() as Node3D
	var skeleton := Motions.skeleton_in(target)
	var mapping := {}
	for bone in skeleton.get_bone_count():
		var original := skeleton.get_bone_name(bone)
		mapping[original] = "recipient_" + original
		skeleton.set_bone_name(bone, mapping[original])
	for player in target.find_children("*", "AnimationPlayer", true, false): player.free()
	assert(target.find_children("*", "AnimationPlayer", true, false).is_empty())
	var rest := skeleton.get_bone_rest(skeleton.find_bone(mapping.LeftUpLeg))
	# A different rest orientation/proportion must be retained by retargeting.
	rest.basis = Basis(Vector3.FORWARD, 0.15) * rest.basis
	rest.origin *= 1.2
	skeleton.set_bone_rest(skeleton.find_bone(mapping.LeftUpLeg), rest)
	for path in Motions.SOURCES:
		assert(Motions.attach(target, path, mapping).is_empty(), "Every donor must work on the unanimated renamed rig")
		var player := target.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var clip := player.get_animation("motion")
		assert(clip.get_track_count() > 10)
		for track in clip.get_track_count():
			var bone := String(clip.track_get_path(track).get_subname(0))
			assert(skeleton.find_bone(bone) >= 0, "Every animation track addresses a recipient bone")
			assert(clip.track_get_type(track) != Animation.TYPE_SCALE_3D, "Donor scales must not deform recipient proportions")
		assert(skeleton.get_bone_rest(skeleton.find_bone(mapping.LeftUpLeg)).is_equal_approx(rest))
	# Feeding the donor rest pose must produce the recipient rest pose, even
	# when bone axes differ; merely copying rotations would fail this check.
	var donor := (load(Motions.SOURCES[0]) as PackedScene).instantiate()
	var src := Motions.skeleton_in(donor)
	var rest_clip := Animation.new()
	var track := rest_clip.add_track(Animation.TYPE_ROTATION_3D)
	rest_clip.track_set_path(track, NodePath("Skeleton:LeftUpLeg"))
	rest_clip.track_insert_key(track, 0, src.get_bone_rest(src.find_bone("LeftUpLeg")).basis.get_rotation_quaternion())
	var converted := Motions.retarget(src, skeleton, rest_clip, NodePath("Skeleton"), mapping)
	var rotation: Quaternion = converted.track_get_key_value(0, 0)
	assert(rotation.is_equal_approx(rest.basis.get_rotation_quaternion()), "Retargeting preserves recipient rest orientation")
	donor.free()
	assert(not Motions.attach(target, Motions.SOURCES[0], {}).is_empty(), "Unknown bone names require an explicit map")
	target.free()
	print("HUMAN MOTION PASS: doorway rejection, shared controller, 10 donors on an unanimated renamed rig, rest orientations and target proportions")
	quit()
