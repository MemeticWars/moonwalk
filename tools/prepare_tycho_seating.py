"""Prepare only the bench and seated Agnes; preserve unrelated city assets."""
from pathlib import Path
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'godot/assets/colonies/tycho/modules'

def points(evaluated=False):
    result = []
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        mesh = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()) if evaluated else obj
        result.extend(mesh.matrix_world @ v.co for v in mesh.data.vertices)
    return result

def bounds(pts):
    return (Vector([min(p[i] for p in pts) for i in range(3)]),
            Vector([max(p[i] for p in pts) for i in range(3)]))

def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))

load(ROOT / 'artifacts/sprites/tychocity/bench.glb')
low, high = bounds(points())
scale = 2.0 / (high.x - low.x)
origin = Vector(((low.x + high.x)/2, (low.y + high.y)/2, low.z))
objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for obj in objects:
    world = obj.matrix_world.copy()
    obj.parent = None
    for v in obj.data.vertices:
        v.co = (world @ v.co - origin) * scale
    obj.matrix_world.identity()
pts = points()
low, high = bounds(pts)
# Seat surface is the central horizontal surface below the backrest.
bpy.context.view_layer.update()
hit, location, *_ = bpy.context.scene.ray_cast(bpy.context.evaluated_depsgraph_get(), Vector((0, 0, 2)), Vector((0, 0, -1)))
seat = location.z if hit else 0.45
upper = [p for p in pts if p.z > seat + 0.18]
back_y = sum(p.y for p in upper) / len(upper)
# Source forward is opposite the high backrest (Godot Z = -Blender Y).
front_z = 1 if back_y > 0 else -1
tris = sum(len(p.vertices)-2 for o in objects for p in o.data.polygons)
bpy.ops.export_scene.gltf(filepath=str(OUT/'bench.glb'), export_format='GLB', export_cameras=False, export_lights=False)
report = json.loads((OUT/'modules.json').read_text())
report['bench'] = dict(size_m=[high.x-low.x, high.z-low.z, high.y-low.y], original_triangles=tris, triangles=tris)
(OUT/'modules.json').write_text(json.dumps(report, indent=2)+'\n')

load(ROOT/'artifacts/sprites/agnes/agnes_Animation_Sit_Cross_Legged_withSkin.glb')
for obj in list(bpy.context.scene.objects):
    if obj.type == 'MESH' and not any(m.type == 'ARMATURE' for m in obj.modifiers):
        bpy.data.objects.remove(obj, do_unlink=True)
rigs = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
for rig in rigs:
    rig.data.pose_position = 'REST'
bpy.context.view_layer.update()
rest_low, rest_high = bounds(points(True))
scale = 1.7 / (rest_high.z-rest_low.z)
for rig in rigs:
    rig.data.pose_position = 'POSE'
bpy.context.scene.frame_set(1)
low, high = bounds(points(True))
hips = rigs[0].matrix_world @ rigs[0].pose.bones['Hips'].head
contact = min(p.z for p in points(True) if abs(p.x-hips.x) < 0.10 and abs(p.y-hips.y) < 0.10 and p.z < hips.z)
root = bpy.data.objects.new('Agnes170cm', None)
bpy.context.collection.objects.link(root)
for obj in list(bpy.context.scene.objects):
    if obj != root and obj.parent is None:
        obj.parent = root
root.scale = (scale,)*3
root.location = (-hips.x*scale, -hips.y*scale, -contact*scale)
bpy.context.view_layer.update()
bpy.ops.export_scene.gltf(filepath=str(OUT/'agnes-seated.glb'), export_format='GLB', export_cameras=False, export_lights=False)
metadata = dict(seat_height=seat, front_z=front_z, standing_height=1.7, seated_size=[(high.x-low.x)*scale,(high.z-low.z)*scale,(high.y-low.y)*scale], scale=scale)
(OUT/'seating.json').write_text(json.dumps(metadata, indent=2)+'\n')
print('SEATING', metadata, flush=True)
