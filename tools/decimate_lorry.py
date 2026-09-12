"""Create a game-resolution version of Meshy's segmented lorry export."""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts" / "sprites" / "lorry" / "Meshy_AI_Lunar Logistics Rover_1788893186_part-segmentation.glb"
OUT_DIR = ROOT / "godot" / "assets" / "lorry"
OUTPUT = OUT_DIR / "lunar_logistics_rover_decimated.glb"


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    low = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in low:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new("Gameplay_decimation", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = 0.075 if len(obj.data.vertices) > 100000 else 0.22
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.name = obj.name.replace(".", "_")
        print("LORRY DECIMATE", obj.name, len(obj.data.vertices), flush=True)
        obj.select_set(False)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in low:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = low[-1]
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", use_selection=True, export_materials="NONE", export_apply=True, export_yup=True)
    print("LORRY DECIMATE PASS", OUTPUT, OUTPUT.stat().st_size, flush=True)


if __name__ == "__main__":
    main()
