"""Build the segmented HQ support rover into a Godot-ready GLB.

The source keeps eight wheels separate.  They remain separate after decimation,
so Godot can rotate them individually without carrying the HQ mesh at runtime.
"""
import bpy
from pathlib import Path

SOURCE = Path(r"D:\projects\moonwalk\artifacts\sprites\track\Meshy_AI_Lunar Logistics Rover_1788897764_part-segmentation.glb")
DESTINATION = Path(r"D:\projects\moonwalk\godot\assets\track\lunar_support_rover_lod.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))

# The source is nested under an import node scaled to 0.0634. Preserve those
# world transforms before discarding the editor-only parents; otherwise Godot
# receives a rover about sixteen times too large.
parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name.lower() != "cube"]
for obj in parts:
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = world
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.select_set(False)

for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH" or obj.name.lower() == "cube":
        bpy.data.objects.remove(obj, do_unlink=True)

parts = sorted((obj for obj in bpy.context.scene.objects if obj.type == "MESH"), key=lambda item: item.name)
assert len(parts) == 10, f"Expected chassis, cabin and eight wheels; got {len(parts)} mesh parts"

for index, obj in enumerate(parts):
    if index == 0:
        obj.name = "track_chassis"
        ratio = 0.012
    elif index == len(parts) - 1:
        obj.name = "track_cabin"
        ratio = 0.012
    else:
        obj.name = f"track_wheel_{index - 1:02d}"
        ratio = 0.020
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    modifier = obj.modifiers.new("Godot_LOD", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)

DESTINATION.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=str(DESTINATION),
    export_format="GLB",
    use_selection=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
)
triangle_count = sum(len(obj.data.polygons) for obj in bpy.context.selected_objects if obj.type == "MESH")
print(f"TRACK LOD: {len(parts)} movable parts, {triangle_count} triangles -> {DESTINATION}")
