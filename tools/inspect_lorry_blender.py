import bpy
from pathlib import Path
from mathutils import Vector

source = Path(__file__).resolve().parents[1] / "artifacts/sprites/lorry"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source / "Meshy_AI_Lunar Logistics Rover_1788893186_part-segmentation.glb"))
for obj in bpy.context.scene.objects:
    if obj.type != "MESH":
        continue
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    low = [min(point[i] for point in corners) for i in range(3)]
    high = [max(point[i] for point in corners) for i in range(3)]
    print(obj.name, len(obj.data.vertices), tuple(round(value, 3) for value in low), tuple(round(value, 3) for value in high))
