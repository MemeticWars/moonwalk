import bpy
from mathutils import Vector

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"D:\projects\moonwalk\artifacts\sprites\track\Meshy_AI_Lunar_Logistics_Rover_0908201853_texture.glb")
mesh = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name != "Cube")
box = [mesh.matrix_world @ Vector(corner) for corner in mesh.bound_box]
center = sum(box, Vector()) / 8
radius = max((point - center).length for point in box)

def look_at(obj, target):
    obj.rotation_euler = (target - obj.location).to_track_quat('-Z', 'Y').to_euler()

bpy.ops.object.light_add(type='AREA', location=(2.4, -2.8, 3.0))
bpy.context.object.data.energy = 1100
bpy.context.object.data.shape = 'DISK'
bpy.context.object.data.size = 3.0
look_at(bpy.context.object, center)
bpy.ops.object.light_add(type='AREA', location=(-2.0, -1.0, 1.2))
bpy.context.object.data.energy = 500
bpy.context.object.data.size = 2.5
look_at(bpy.context.object, center)
bpy.ops.object.camera_add(location=(2.7, -3.3, 2.1))
camera = bpy.context.object
look_at(camera, center)
camera.data.lens = 52
bpy.context.scene.camera = camera
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 900
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.world.color = (0.035, 0.04, 0.055)
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = r"D:\projects\moonwalk\artifacts\track_preview.png"
bpy.ops.wm.save_as_mainfile(filepath=r"D:\projects\moonwalk\artifacts\track_preview.blend")
bpy.ops.render.render(write_still=True)
