from pathlib import Path
import bpy, json
from mathutils import Vector
root = Path(__file__).resolve().parents[1]
folder = root/'godot/assets/colonies/tycho/modules'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(folder/'bench.glb'))
bench_objects = set(bpy.context.scene.objects)
bench_height_scale = 0.72
agnes_lift = 0.05
book_scale = 0.75
for obj in bench_objects:
    if obj.parent is None:
        # Godot Y is Blender Z.
        obj.scale.z *= bench_height_scale
before = set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath=str(folder/'agnes-seated.glb'))
agnes_objects = set(bpy.context.scene.objects)-before
for obj in agnes_objects:
    if obj.parent is None:
        obj.location.z += json.loads((folder/'seating.json').read_text())['seat_height']*bench_height_scale+0.005+agnes_lift
bpy.context.scene.frame_set(1)
bpy.context.view_layer.update()
agnes_points = []
for obj in agnes_objects:
    if obj.type == 'MESH':
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        agnes_points += [evaluated.matrix_world @ v.co for v in evaluated.data.vertices]
print('SEATED AGNES WORLD Z', min(p.z for p in agnes_points), max(p.z for p in agnes_points), flush=True)
before = set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath=str(folder/'voyages-extraordinaires.glb'))
book_objects = set(bpy.context.scene.objects)-before
for obj in book_objects:
    if obj.parent is None:
        # Godot (x,y,z) maps to Blender (x,z,-y). The book is a child of Agnes.
        obj.location = (0.0, -0.30, 0.36 + json.loads((folder/'seating.json').read_text())['seat_height']*bench_height_scale+0.005+agnes_lift)
        obj.rotation_euler = (0.0, 0.0, 0.0)
        obj.rotation_euler.x = -1.36136  # Godot 78 degrees around X
        obj.scale *= book_scale
bpy.ops.object.camera_add(location=(3,-4,2.5))
cam=bpy.context.object
cam.rotation_euler=(Vector((0,0,0.85))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='ORTHO'
cam.data.ortho_scale=3.0
scene=bpy.context.scene
scene.camera=cam
scene.render.engine='BLENDER_WORKBENCH'
scene.display.shading.light='STUDIO'
scene.display.shading.color_type='MATERIAL'
scene.render.resolution_x=900
scene.render.resolution_y=900
scene.render.resolution_percentage=100
scene.render.filepath=str(root/'artifacts/seating_preview.png')
bpy.ops.render.render(write_still=True)
