"""Blender --background --python tools/prepare_tycho_habitat_tunnel.py.

Prepares the Meshy habitat-module GLB as the airlock tunnel connector used
between Tycho's domes (tycho_east_annex.gd). The source's long axis is
Blender X; normalize it to 20 m, the fixed centre-to-centre tunnel gap every
connected dome pair in the annex was sited to (radius_a + 20 + radius_b).
"""
from pathlib import Path
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/sprites/tychocity/Meshy_AI_Lunar_Habitat_Module_0912233051_texture.glb"
OUTPUT = ROOT / "godot/assets/colonies/tycho/modules/habitat-tunnel.glb"
MODULES_JSON = ROOT / "godot/assets/colonies/tycho/modules/modules.json"
TUNNEL_GAP_M = 20.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
worlds = {o.name: o.matrix_world.copy() for o in objects}
for obj in objects:
    world = worlds[obj.name]
    obj.parent = None
    for v in obj.data.vertices:
        v.co = world @ v.co
    obj.matrix_world.identity()
for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH":
        bpy.data.objects.remove(obj, do_unlink=True)
points = [v.co for o in objects for v in o.data.vertices]
low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
size = high - low
print("HABITAT TUNNEL SOURCE SIZE", tuple(size), flush=True)
# Long axis is Blender X here (the corridor's length); normalize on it.
scale = TUNNEL_GAP_M / size.x
origin = Vector(((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, low.z))
original = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
for obj in objects:
    for v in obj.data.vertices:
        v.co = (v.co - origin) * scale
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_apply=True,
                          export_cameras=False, export_lights=False)
low, high = (Vector((min(v.co[i] for o in objects for v in o.data.vertices) for i in range(3))),
             Vector((max(v.co[i] for o in objects for v in o.data.vertices) for i in range(3))))
size = high - low
triangles = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
entry = {"size_m": [size.x, size.z, size.y], "original_triangles": original, "triangles": triangles}
print("HABITAT TUNNEL FINAL", entry, flush=True)
data = json.loads(MODULES_JSON.read_text())
data["habitat-tunnel"] = entry
MODULES_JSON.write_text(json.dumps(data, indent=2) + "\n")
