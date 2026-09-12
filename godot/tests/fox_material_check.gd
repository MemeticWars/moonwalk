extends SceneTree

func _initialize() -> void:
	var fox := (load("res://assets/colonies/tycho/modules/fox.glb") as PackedScene).instantiate() as Node3D
	for m: MeshInstance3D in fox.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		print("MESH ", m.name, " surfaces=", m.mesh.get_surface_count())
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			print("  surface ", i, " material=", mat)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				print("    vertex_color_use_as_albedo=", bm.vertex_color_use_as_albedo)
				print("    albedo_color=", bm.albedo_color)
				print("    shading_mode=", bm.shading_mode)
			var arrays := m.mesh.surface_get_arrays(i)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			print("    color array size=", colors.size())
			if colors.size() > 0:
				var seen := {}
				for c in colors:
					seen[c] = true
				print("    distinct colors sample=", Array(seen.keys()).slice(0, 6))
	quit()
