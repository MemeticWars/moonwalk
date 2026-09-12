import bpy
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath='D:/projects/moonwalk/artifacts/sprites/agnes/agnes_Animation_Sit_Cross_Legged_withSkin.glb')
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
print('ACTIONS', [(a.name, list(a.frame_range)) for a in bpy.data.actions])
for frame in [1, 15, 30, 45, 60]:
    bpy.context.scene.frame_set(frame)
    pts = []
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            ob = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            pts += [ob.matrix_world @ v.co for v in ob.data.vertices]
    print('FRAME', frame, 'BOUNDS', [(min(p[i] for p in pts),max(p[i] for p in pts)) for i in range(3)])
    print('BONES', [(b.name,tuple(rig.matrix_world @ b.head)) for b in rig.pose.bones if any(t in b.name for t in ['Hips','Head','UpLeg','Foot'])])
