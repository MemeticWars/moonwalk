"""Extract the painted base-colour map embedded in Meshy's HQ lorry GLB."""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts" / "sprites" / "lorry" / "Meshy_AI_Lunar_Logistics_Rover_0908185912_texture.glb"
OUT = ROOT / "godot" / "assets" / "lorry" / "lunar_lorry_basecolor.png"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
materials = [m for m in bpy.data.materials if m.use_nodes]
principled = materials[0].node_tree.nodes.get("Principled BSDF")
image = principled.inputs["Base Color"].links[0].from_node.image
OUT.parent.mkdir(parents=True, exist_ok=True)
image.save_render(filepath=str(OUT))
print("LORRY TEXTURE PASS", image.name, image.size[:], OUT, OUT.stat().st_size, flush=True)
