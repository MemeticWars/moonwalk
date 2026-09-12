import bpy
from pathlib import Path
from mathutils import Vector
for path in [Path(r"D:\projects\moonwalk\artifacts\sprites\tychocity\tomato.glb"), Path(r"D:\projects\moonwalk\artifacts\sprites\tychocity\tomatoes.glb")]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    points = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    print(path.name, high - low, sum(len(poly.vertices) - 2 for o in objects for poly in o.data.polygons), flush=True)
