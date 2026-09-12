"""Prepare the supplied Azure Frontier Colony for the Tycho Station sector.

Run: Blender --background --python tools/prepare_tycho_station.py
"""
from pathlib import Path
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/sprites/tychocity/Meshy_AI_Azure_Frontier_Colony_0909202644_texture.glb"
OUTPUT = ROOT / "godot/assets/colonies/tycho"
TARGET_WIDTH_M = 100.0


def bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))), Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    low, high = bounds(objects)
    scale = TARGET_WIDTH_M / max(high.x - low.x, high.y - low.y)
    origin = Vector(((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, low.z))

    for obj in objects:
        world = obj.matrix_world.copy()
        for vertex in obj.data.vertices:
            vertex.co = (world @ vertex.co - origin) * scale
        obj.matrix_world.identity()
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new("Tycho_game_lod", "DECIMATE")
        modifier.ratio = min(1.0, 120000 / max(1, len(obj.data.polygons)))
        bpy.ops.object.modifier_apply(modifier=modifier.name)

    # Decimation can push a few triangles below the original floor. Re-seat
    # the final mesh so its lowest point is exactly the sector ground plane.
    low, _high = bounds(objects)
    for obj in objects:
        for vertex in obj.data.vertices:
            vertex.co.z -= low.z

    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT / "tycho_station.glb"),
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    low, high = bounds(objects)
    metadata = {
        "name": "Tycho Station",
        "latitude": -43.38,
        "longitude": -10.63,
        "site_basis": "flat impact-melt floor east-northeast of Tycho central peak; approximate LOLA/LDEM_4 placement",
        "model_source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
        "target_width_m": TARGET_WIDTH_M,
        "aabb_m": {"min": list(low), "max": list(high)},
        "texture_status": "Source GLB provides embedded base-color, metallic-roughness and normal maps.",
    }
    (OUTPUT / "tycho_station.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("TYCHO STATION EXPORT", OUTPUT, flush=True)


if __name__ == "__main__":
    main()
