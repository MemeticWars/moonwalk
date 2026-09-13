"""Blender --background --python tools/prepare_tycho_fish.py.

Prepares the pond/stream fish GLB: drops the stray unmaterialed "Icosphere"
placeholder mesh and the (animation-less) armature, bakes world transforms,
and normalizes body length (long axis, source X) to 0.30 m -- a small
ornamental pond fish. Centred on its own bounding-box centre (not seated on
Z=0 like a building module): fish are placed by a floating centre point,
not a ground contact point.
"""
from pathlib import Path
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/sprites/fish/fish_Character_output.glb"
OUTPUT = ROOT / "godot/assets/colonies/tycho/modules/fish.glb"
MODULES_JSON = ROOT / "godot/assets/colonies/tycho/modules/modules.json"
BODY_LENGTH_M = 0.30

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
objects = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name != "Icosphere"]
worlds = {o.name: o.matrix_world.copy() for o in objects}
for obj in objects:
    world = worlds[obj.name]
    obj.parent = None
    for v in obj.data.vertices:
        v.co = world @ v.co
    obj.matrix_world.identity()
for obj in list(bpy.context.scene.objects):
    if obj not in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
points = [v.co for o in objects for v in o.data.vertices]
low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
size = high - low
print("FISH SOURCE SIZE", tuple(size), flush=True)
scale = BODY_LENGTH_M / size.x
origin = (low + high) * 0.5
original = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
for obj in objects:
    for v in obj.data.vertices:
        v.co = (v.co - origin) * scale
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_apply=True,
                          export_cameras=False, export_lights=False)
low = Vector((min(v.co[i] for o in objects for v in o.data.vertices) for i in range(3)))
high = Vector((max(v.co[i] for o in objects for v in o.data.vertices) for i in range(3)))
size = high - low
triangles = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
entry = {"size_m": [size.x, size.z, size.y], "original_triangles": original, "triangles": triangles}
print("FISH FINAL", entry, flush=True)
data = json.loads(MODULES_JSON.read_text())
data["fish"] = entry
MODULES_JSON.write_text(json.dumps(data, indent=2) + "\n")
