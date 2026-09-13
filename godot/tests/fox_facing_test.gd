extends SceneTree

const FOXY := preload("res://assets/colonies/tycho/modules/foxy_model_Animation_Walking_withSkin.glb")

func _init() -> void:
	var fox := FOXY.instantiate() as Node3D
	var skeleton := fox.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head := skeleton.get_bone_global_pose(skeleton.find_bone("head")).origin
	var hips := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	# fox.gd uses the normal Godot forward convention (local -Z): the foxy
	# skeleton's head must therefore be ahead of its hips on the negative Z axis.
	assert(head.z < hips.z, "Foxy must face local -Z so walking faces its travel direction")
	fox.free()
	print("FOXY FACING PASS: textured foxy model faces local -Z")
	quit()
