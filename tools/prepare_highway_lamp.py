"""Make a shared, metre-scaled gameplay mesh from the supplied lamp GLB.
Run using Blender --background --python tools/prepare_highway_lamp.py.
"""
from pathlib import Path
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/sprites/lamp/Meshy_AI_Modern_Industrial_Str_0909194644_texture_lowpoly.glb"
OUTPUT = ROOT / "godot/assets/roads/lamp"
OUTPUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
vertices = [obj.matrix_world @ v.co for obj in objects for v in obj.data.vertices]
bottom = min(v.z for v in vertices)
top = max(v.z for v in vertices)
base = [v for v in vertices if v.z < bottom + (top - bottom) * 0.025]
origin = Vector((sum(v.x for v in base) / len(base), sum(v.y for v in base) / len(base), bottom))
scale = 12.0 / (top - bottom)
for obj in objects:
    transform = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        vertex.co = (transform @ vertex.co - origin) * scale
    obj.matrix_world.identity()
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("Road_lamp_LOD", "DECIMATE")
    modifier.ratio = min(1.0, 3500 / max(1, len(obj.data.polygons)))
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    print("LAMP MESH", len(obj.data.vertices), len(obj.data.polygons), flush=True)
# Normalize the supplied arm direction as well as its height and foot origin.
# This source happens to face -X despite the reference image's perspective.
upper = [v.co.x for obj in objects for v in obj.data.vertices if v.co.z > 11.0]
if abs(min(upper)) > abs(max(upper)):
    for obj in objects:
        for vertex in obj.data.vertices:
            vertex.co.x *= -1
            vertex.co.y *= -1
for image in bpy.data.images:
    if image.size[0] > 1024 or image.size[1] > 1024:
        image.scale(1024, 1024)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT / "industrial_lamp.glb"), export_format="GLB", export_apply=True, export_yup=True)
metadata = {"height_m": 12.0, "source": str(SOURCE.relative_to(ROOT)), "arm_direction": "+X", "source_vertices": len(vertices)}
(OUTPUT / "lamp.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
print("LAMP EXPORT", OUTPUT, flush=True)
