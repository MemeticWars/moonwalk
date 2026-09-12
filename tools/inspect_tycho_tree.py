"""Inspect tree materials before converting them for Tycho."""
import bpy
from pathlib import Path

SOURCE = Path(r"D:\projects\elvenpass\godot_playable\assets\backgrounds\forest\fagus_3k.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
for material in bpy.data.materials:
    print(material.name, "base", tuple(round(v, 3) for v in material.diffuse_color), flush=True)
    if material.use_nodes:
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image:
                print(" texture", node.image.name, node.image.size[:], flush=True)
