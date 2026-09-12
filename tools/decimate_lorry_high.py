"""Build a manageable UV-preserving proxy of the painted HQ rover."""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts" / "sprites" / "lorry" / "Meshy_AI_Lunar_Logistics_Rover_0908185912_texture.glb"
OUTPUT = ROOT / "godot" / "assets" / "lorry" / "lunar_lorry_hq_uv_proxy.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
modifier = obj.modifiers.new("UV_proxy_decimation", "DECIMATE")
modifier.decimate_type = "COLLAPSE"
modifier.ratio = 0.12
bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", use_selection=True, export_materials="EXPORT", export_apply=True, export_yup=True)
print("LORRY HQ UV PROXY PASS", len(obj.data.vertices), len(obj.data.polygons), OUTPUT.stat().st_size, flush=True)
