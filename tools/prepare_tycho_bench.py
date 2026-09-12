from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[1]
source = root / "artifacts/sprites/tychocity/bench.glb"
output = root / "godot/assets/colonies/tycho/modules/bench.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
low = Vector((min(p[i] for p in points) for i in range(3)))
high = Vector((max(p[i] for p in points) for i in range(3)))
size = high - low
print("BENCH SOURCE SIZE", tuple(size), flush=True)
# Keep the supplied bench proportions and normalize its seat height to 0.45 m.
scale = 0.45 / size.z if size.z > 0.001 else 1.0
origin = Vector(((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, low.z))
for obj in objects:
    world = obj.matrix_world.copy()
    obj.parent = None
    for v in obj.data.vertices:
        v.co = (world @ v.co - origin) * scale
    obj.matrix_world.identity()
for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH":
        bpy.data.objects.remove(obj, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", export_apply=True, export_cameras=False, export_lights=False)
