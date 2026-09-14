extends Node3D
## Wandering park NPC: walks between random points inside Tycho's west tree
## garden, pauses, and sometimes dips its head as if sniffing the ground.
## The walk clip ("Armature|Unreal Take|baselayer", the only animation in
## foxy_model_Animation_Walking_withSkin.glb) has no NET root motion over a full loop -- position here is
## fully script-driven and the clip just plays in place. (The recolour
## pipeline separately rescales the clip's location fcurves by 0.01 to match
## the baked-down rest pose -- without that, playing the clip made the whole
## model visibly jump by up to ~1 m within a few frames.)

const FOX_SCENE := preload("res://assets/colonies/tycho/modules/foxy_model_Animation_Walking_withSkin.glb")
const Site := preload("res://scripts/tycho_site.gd")
const TARGET_HEIGHT_M := 0.40
const WALK_SPEED := 0.5  # m/s -- a small animal's ambling pace
const ARRIVE_DIST := 0.2
# World-space XZ box for the west tree garden (Site.CENTER + the _layout()
# park-tree grid: x in [-26,-11], z(local) in [-76,-12] -> world z = Site.CENTER.y+local),
# inset so wander targets don't land inside a trunk or spill onto the road.
const PARK_MIN := Site.CENTER + Vector2(-25.0, -74.5)
const PARK_MAX := Site.CENTER + Vector2(-12.0, -13.5)
const TREE_CLEARANCE := 1.6

var terrain: Node3D
var _body: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone := -1
var _target := Vector2.ZERO
var _state := "walk"
var _state_timer := 0.0
var _sniff_rest := Quaternion.IDENTITY
var _rng := RandomNumberGenerator.new()
var _tree_centers: PackedVector2Array = PackedVector2Array()
var _foot_offset := 0.0

func _ready() -> void:
	add_to_group("fox_npc")
	_rng.randomize()
	for x in [-26.0, -21.0, -16.0, -11.0]:
		for z in [-76.0, -68.0, -60.0, -52.0, -44.0, -36.0, -28.0, -20.0, -12.0]:
			_tree_centers.append(Vector2(Site.CENTER.x + x, Site.CENTER.y + z))
	_body = FOX_SCENE.instantiate()
	add_child(_body)
	_anim = _body.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = _body.find_children("*", "Skeleton3D", true, false)[0]
	_head_bone = _skeleton.find_bone("head")
	_scale_to_height()
	var start := _random_park_point()
	position = Vector3(start.x, terrain.height_at(start.x, start.y) - _foot_offset, start.y)
	_pick_new_target()

func _scale_to_height() -> void:
	# mesh.get_aabb() on this GLB's skinned mesh is NOT a measurement of the
	# fox at all: confirmed by instrumenting this function, it returns a
	# degenerate ~5e-5 m box on every axis (bind-pose data collapsed near the
	# origin, unrelated to which axis is "up"). A prior fix here swapped
	# box.size.z for box.size.y believing it was an axis mixup; both numbers
	# were equally meaningless, which is why the fox stayed wrong after that
	# fix -- the scale it produced (~7273x) just happened to look plausible.
	# The Skeleton3D's bone rest pose IS correctly scaled (see
	# probe_foxy.log / [[fox-park-npc]]), so measure real size from bone
	# positions instead of the mesh's cached AABB.
	var box := AABB()
	var seeded := false
	for i in _skeleton.get_bone_count():
		var p: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(i).origin
		var b := AABB(p, Vector3.ZERO)
		box = b if not seeded else box.merge(b)
		seeded = true
	var scale := TARGET_HEIGHT_M / maxf(box.size.y, 0.000000001)
	_body.scale = Vector3.ONE * scale
	# box.position.y is the lowest bone's offset from the model's own local
	# origin (measured at scale=1); without this the paws would hover/sink by
	# that offset once scaled up. Bone positions undershoot the true paw
	# contact point slightly (no bone sits exactly at the ground), so this is
	# an approximation, not exact -- acceptable for a small background NPC.
	_foot_offset = box.position.y * scale

func _clear_of_trees(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for t: Vector2 in _tree_centers:
		if p.distance_squared_to(t) < TREE_CLEARANCE * TREE_CLEARANCE:
			return false
	return true

func _random_park_point() -> Vector2:
	for i in 12:
		var x := _rng.randf_range(PARK_MIN.x, PARK_MAX.x)
		var z := _rng.randf_range(PARK_MIN.y, PARK_MAX.y)
		if _clear_of_trees(x, z):
			return Vector2(x, z)
	return Vector2(_rng.randf_range(PARK_MIN.x, PARK_MAX.x), _rng.randf_range(PARK_MIN.y, PARK_MAX.y))

func _pick_new_target() -> void:
	_target = _random_park_point()

func _process(delta: float) -> void:
	match _state:
		"walk": _do_walk(delta)
		"pause": _do_pause(delta)
		"sniff": _do_sniff(delta)

func _do_walk(delta: float) -> void:
	if not _anim.is_playing() or _anim.current_animation != "Armature|Unreal Take|baselayer":
		_anim.play("Armature|Unreal Take|baselayer")
	var here := Vector2(position.x, position.z)
	var to_target := _target - here
	var dist := to_target.length()
	if dist < ARRIVE_DIST:
		_enter_pause()
		return
	var dir := to_target / dist
	here += dir * WALK_SPEED * delta
	position.x = here.x
	position.z = here.y
	position.y = terrain.height_at(here.x, here.y) - _foot_offset
	# The foxy GLB faces local +Z in Godot (verified empirically: with the old
	# "+PI" here, a chase camera placed behind the direction of travel saw the
	# fox's face, not its back -- it was walking backwards). No +PI needed.
	rotation.y = atan2(dir.x, dir.y)

func _enter_pause() -> void:
	_state = "pause"
	_state_timer = _rng.randf_range(1.5, 4.0)
	_anim.pause()
	if _rng.randf() < 0.55:
		_enter_sniff()

func _do_pause(_delta: float) -> void:
	_state_timer -= _delta
	if _state_timer <= 0.0:
		_pick_new_target()
		_state = "walk"

func _enter_sniff() -> void:
	_state = "sniff"
	_state_timer = _rng.randf_range(1.8, 3.2)
	# Captured once: the AnimationPlayer is paused for the whole "sniff"
	# state, so nothing else writes this bone -- re-reading get_bone_pose_
	# rotation() every frame would read back our OWN previous dip and
	# compound it instead of oscillating around the paused walk pose.
	_sniff_rest = _skeleton.get_bone_pose_rotation(_head_bone)

func _do_sniff(delta: float) -> void:
	_state_timer -= delta
	# A slow head-down-and-back bob, like nosing at the ground -- procedural,
	# since the source asset ships only the one walk clip.
	var phase := 1.0 - clampf(_state_timer / 2.5, 0.0, 1.0)
	var dip := sin(phase * TAU * 1.5) * 0.35 + 0.35
	_skeleton.set_bone_pose_rotation(_head_bone, _sniff_rest * Quaternion(Vector3.RIGHT, dip))
	if _state_timer <= 0.0:
		_skeleton.set_bone_pose_rotation(_head_bone, _sniff_rest)
		_pick_new_target()
		_state = "walk"
