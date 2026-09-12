"""Scale the supplied Jules Verne GLB for use on seated Agnes's lap."""
from pathlib import Path
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/sprites/book/Meshy_AI_Voyages_Extraordinair_0911001405_texture.glb"
OUTPUT = ROOT / "godot/assets/colonies/tycho/modules/voyages-extraordinaires.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
worlds = {o.name: o.matrix_world.copy() for o in objects}
points = [worlds[o.name] @ v.co for o in objects for v in o.data.vertices]
low = Vector([min(p[i] for p in points) for i in range(3)])
high = Vector([max(p[i] for p in points) for i in range(3)])
size = high - low
scale = 0.30 / max(size)
centre = (low + high) * 0.5
triangles = sum(len(poly.vertices) - 2 for o in objects for poly in o.data.polygons)
for obj in objects:
    world = worlds[obj.name]
    obj.parent = None
    for vertex in obj.data.vertices:
        vertex.co = (world @ vertex.co - centre) * scale
    obj.matrix_world.identity()
for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH":
        bpy.data.objects.remove(obj, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_apply=True,
                          export_cameras=False, export_lights=False)
final_size = size * scale
metadata = {
    "size_m": [final_size.x, final_size.z, final_size.y],
    "triangles": triangles,
    "source": str(SOURCE.relative_to(ROOT)),
}
(OUTPUT.with_suffix(".json")).write_text(json.dumps(metadata, indent=2) + "\n")
print("TYCHO BOOK", metadata, flush=True)
