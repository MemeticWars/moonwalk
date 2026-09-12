extends RefCounted

## Shared motion donors. Their meshes are never used for a different character.
const SOURCES := [
	"res://assets/agnes/fitted/agnes_suit_Animation_Spear_Walk_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_Animation_Running_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_turn_left_Animation_Idle_Turn_Left_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_turn_right_Animation_Idle_Turn_Right_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_Animation_Idle_5_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_Animation_Jump_Over_Obstacle_2_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_Animation_climbing_up_wall_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_Animation_Ladder_Climb_Finish_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_Animation_Crawl_and_Look_Back_withSkin.glb",
	"res://assets/agnes/fitted/agnes_suit_Animation_Stand_Up2_withSkin.glb",
]
const REQUIRED := ["Hips", "Spine", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]
const ALIASES := {"pelvis": "hips", "spine1": "spine01", "spine2": "spine02", "leftupperleg": "leftupleg", "rightupperleg": "rightupleg", "leftlowerleg": "leftleg", "rightlowerleg": "rightleg", "leftupperarm": "leftarm", "rightupperarm": "rightarm", "leftlowerarm": "leftforearm", "rightlowerarm": "rightforearm"}

static func _canonical(bone: String) -> String:
	var key := bone.get_slice(":", bone.get_slice_count(":") - 1).to_lower().replace("mixamorig", "").replace("_", "").replace("-", "").replace(" ", "")
	return ALIASES.get(key, key)

static func find_bone(skeleton: Skeleton3D, source_name: String, mapping: Dictionary = {}) -> int:
	if mapping.has(source_name): return skeleton.find_bone(mapping[source_name])
	for bone in skeleton.get_bone_count():
		if _canonical(skeleton.get_bone_name(bone)) == _canonical(source_name): return bone
	return -1

static func skeleton_in(visual: Node) -> Skeleton3D:
	if visual is Skeleton3D: return visual
	var found := visual.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null

static func _parent_rotation(skeleton: Skeleton3D, bone: int) -> Quaternion:
	var parent := skeleton.get_bone_parent(bone)
	return skeleton.get_bone_global_rest(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY

static func retarget(source: Skeleton3D, target: Skeleton3D, clip: Animation, target_path: NodePath, mapping: Dictionary = {}) -> Animation:
	var result := Animation.new()
	result.length = clip.length
	result.loop_mode = clip.loop_mode
	var source_hips := source.find_bone("Hips")
	var target_hips := find_bone(target, "Hips", mapping)
	var source_foot := source.find_bone("LeftFoot")
	var target_foot := find_bone(target, "LeftFoot", mapping)
	if source_hips < 0 or target_hips < 0 or source_foot < 0 or target_foot < 0: return result
	var source_size := source.get_bone_global_rest(source_hips).origin.distance_to(source.get_bone_global_rest(source_foot).origin)
	var target_size := target.get_bone_global_rest(target_hips).origin.distance_to(target.get_bone_global_rest(target_foot).origin)
	var ratio := target_size / maxf(source_size, 0.001)
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		if path.get_subname_count() != 1: continue
		var name := String(path.get_subname(0))
		var src := source.find_bone(name)
		var dst := find_bone(target, name, mapping)
		if src < 0 or dst < 0: continue
		var type := clip.track_get_type(track)
		# Preserve target limb lengths: animation translations/scales of other
		# joints belong to the donor's proportions, not the recipient's body.
		if type != Animation.TYPE_ROTATION_3D and not (type == Animation.TYPE_POSITION_3D and src == source_hips): continue
		var out := result.add_track(type)
		result.track_set_path(out, NodePath(String(target_path) + ":" + target.get_bone_name(dst)))
		result.track_set_interpolation_type(out, clip.track_get_interpolation_type(track))
		var src_rest := source.get_bone_rest(src)
		var dst_rest := target.get_bone_rest(dst)
		var src_parent := _parent_rotation(source, src)
		var dst_parent := _parent_rotation(target, dst)
		for key in clip.track_get_key_count(track):
			var value: Variant = clip.track_get_key_value(track, key)
			if type == Animation.TYPE_ROTATION_3D:
				var delta: Quaternion = src_parent * (value as Quaternion) * src_rest.basis.get_rotation_quaternion().inverse() * src_parent.inverse()
				value = (dst_parent.inverse() * delta * dst_parent * dst_rest.basis.get_rotation_quaternion()).normalized()
			else:
				value = dst_rest.origin + dst_parent.inverse() * (src_parent * ((value as Vector3) - src_rest.origin)) * ratio
			result.track_insert_key(out, clip.track_get_key_time(track, key), value, clip.track_get_key_transition(track, key))
	return result

static func attach(visual: Node3D, donor_path: String, mapping: Dictionary = {}) -> String:
	var target := skeleton_in(visual)
	if target == null: return "Model has no Skeleton3D"
	var assigned: Array[int] = []
	for name in REQUIRED:
		var bone := find_bone(target, name, mapping)
		if bone < 0: return "Missing humanoid bone '%s'; provide humanoid_bone_map" % name
		if bone in assigned: return "Several required bones map to '%s'" % target.get_bone_name(bone)
		assigned.append(bone)
	var scene := load(donor_path) as PackedScene
	if scene == null: return "Missing motion donor: " + donor_path
	var donor := scene.instantiate()
	var source := skeleton_in(donor)
	var donor_players := donor.find_children("*", "AnimationPlayer", true, false)
	if source == null or donor_players.is_empty():
		donor.free()
		return "Motion donor has no skeleton/animations"
	var source_player := donor_players[0] as AnimationPlayer
	var clip: Animation
	for name in source_player.get_animation_list():
		if name != "RESET":
			clip = source_player.get_animation(name)
			break
	if clip == null:
		donor.free()
		return "Motion donor has no action clip"
	var converted := retarget(source, target, clip, visual.get_path_to(target), mapping)
	donor.free()
	if converted.get_track_count() == 0: return "No compatible motion tracks"
	for tree in visual.find_children("*", "AnimationTree", true, false): tree.free()
	for old in visual.find_children("*", "AnimationPlayer", true, false): old.free()
	var player := AnimationPlayer.new()
	player.name = "SharedMotions"
	visual.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation("motion", converted)
	player.add_animation_library("", library)
	return ""
