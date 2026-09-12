"""Project the painted high-resolution rover material onto the segmented rover.

The segmentation asset keeps its four wheels as separate mesh nodes.  It is
scaled to the dimensions of the textured source before baking, so the GLB
written below is directly usable by Godot while retaining those moving parts.
"""
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts" / "sprites" / "lorry"
OUTPUT_DIR = ROOT / "godot" / "assets" / "lorry"
LOW_PATH = ROOT / "godot" / "assets" / "lorry" / "lunar_logistics_rover_decimated.glb"
HIGH_PATH = ROOT / "godot" / "assets" / "lorry" / "lunar_lorry_hq_uv_proxy.glb"
OUTPUT = OUTPUT_DIR / "lunar_logistics_rover_baked.glb"


def meshes() -> list:
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def bounds(objects: list) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return (
        Vector((min(point[i] for point in points) for i in range(3))),
        Vector((max(point[i] for point in points) for i in range(3))),
    )


def select_only(objects: list, active=None) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active or objects[-1]


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(HIGH_PATH))
    high = meshes()
    for obj in high:
        obj.name = "paint_source_" + obj.name
    high_min, high_max = bounds(high)
    high_center = (high_min + high_max) * 0.5

    bpy.ops.import_scene.gltf(filepath=str(LOW_PATH))
    low = [obj for obj in meshes() if obj not in high]
    for obj in low:
        obj.name = obj.name.replace(" ", "_")
    low_min, low_max = bounds(low)
    low_center = (low_min + low_max) * 0.5
    high_size = high_max - high_min
    low_size = low_max - low_min
    # Meshy's part-segmentation export is uniformly tiny.  Match its long axis
    # to the painted source; keeping a uniform factor preserves wheel circles.
    scale = max(high_size) / max(low_size)
    for obj in low:
        obj.location = high_center + (obj.location - low_center) * scale
        obj.scale *= scale
    print("LORRY BAKE alignment", tuple(round(v, 4) for v in high_size), tuple(round(v, 4) for v in low_size), round(scale, 5))

    # The input is a pre-decimated version of the supplied segmentation export.
    source_mesh = high[0]
    source_material = source_mesh.data.materials[0]
    for obj in low:
        select_only([obj], obj)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if not obj.data.uv_layers:
            obj.data.uv_layers.new(name="ProjectedUV")
        transfer = obj.modifiers.new("High_resolution_texture_projection", "DATA_TRANSFER")
        transfer.object = source_mesh
        transfer.use_loop_data = True
        transfer.data_types_loops = {"UV"}
        transfer.loop_mapping = "POLYINTERP_NEAREST"
        bpy.ops.object.modifier_apply(modifier=transfer.name)
        obj.data.materials.clear()
        obj.data.materials.append(source_material)
        print("LORRY PROJECT", obj.name, len(obj.data.vertices), flush=True)

    for obj in high:
        bpy.data.objects.remove(obj, do_unlink=True)
    # Keep names stable for the Godot wheel-pivot script.
    for obj in low:
        obj.name = obj.name.replace(".", "_")
    select_only(low, low[-1])
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_materials="EXPORT",
        export_apply=True,
        export_yup=True,
    )
    print("LORRY BAKE PASS", OUTPUT, OUTPUT.stat().st_size)


if __name__ == "__main__":
    main()
