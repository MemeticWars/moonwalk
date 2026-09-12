import bpy
from pathlib import Path
from mathutils import Vector
root=Path(r'D:/projects/moonwalk')
for tag, pattern in [('central','*Orbital_Command*'),('L','*Modular_Frontier*'),('garden','*Futuristic_Garden*')]:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(next((root/'artifacts/sprites/tychocity').glob(pattern))))
 obs=[o for o in bpy.context.scene.objects if o.type=='MESH']
 pts=[o.matrix_world@Vector(c) for o in obs for c in o.bound_box]
 lo=Vector([min(p[i] for p in pts) for i in range(3)]); hi=Vector([max(p[i] for p in pts) for i in range(3)])
 center=(lo+hi)/2; size=max(hi-lo)
 bpy.ops.object.camera_add(location=center+Vector((1,-1,0.8))*size*1.7)
 camera=bpy.context.object; camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler(); camera.data.type='ORTHO'; camera.data.ortho_scale=size*1.6
 scene=bpy.context.scene; scene.camera=camera; scene.render.engine='BLENDER_WORKBENCH'; scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_shadows=True; scene.display.shading.show_cavity=True
 scene.render.resolution_x=640; scene.render.resolution_y=640; scene.render.resolution_percentage=100; scene.render.filepath=str(root/f'artifacts/tycho_source_{tag}.png'); bpy.ops.render.render(write_still=True)

