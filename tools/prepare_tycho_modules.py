"""Blender --background --python tools/prepare_tycho_modules.py.

Keep the supplied UVs/materials, bake metre units and produce reusable city modules.
The panorama is a composition reference, never a billboard in the game.
"""
from pathlib import Path
import json
import bpy
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/sprites/tychocity"
OUTPUT = ROOT / "godot/assets/colonies/tycho/modules"
# Name, dimension to normalize, metres. Preserve original geometry and textures.
MODULES = [
    ("block-of-flats", "height", 30.0),
    ("central-building", "width", 32.0),
    ("twin-houses", "width", 18.0),
    ("link-between-block-of-flats", "width", 14.0),
    ("fotovoltaic-panels", "width", 22.0),
    ("tank", "height", 6.0),
    ("radio-mast", "height", 28.0),
    ("central-house", "width", 51.0),
    ("l-shape-building", "width", 24.0),
    ("park-birch", "height", 7.5),
    ("park-pine", "height", 13.5),
    ("park-beech", "height", 12.0),
    ("street-lamp", "height", 6.0),
    ("greenhouse", "greenhouse", 24.0),
    ("tomato", "crop", 1.0),
    ("tomatoes", "crop", 1.0),
]
SOURCES = {
    "central-house": "Meshy_AI_Orbital_Command_Hub_0910201153_texture.glb",
    "l-shape-building": "Meshy_AI_Modular_Frontier_Habi_0910201755_texture.glb",
    "park-birch": "D:/projects/elvenpass/godot_playable/assets/backgrounds/forest/birch_tree.glb",
    "park-pine": "D:/projects/elvenpass/godot_playable/addons/proton_scatter/demos/assets/models/pine_tree.glb",
    "park-beech": "D:/projects/elvenpass/godot_playable/assets/backgrounds/forest/fagus_3k.glb",
    "greenhouse": "szklarnia.glb",
    "tomato": "tomato.glb",
    "tomatoes": "tomatoes.glb",
}


def bounds(objects):
    points = [v.co for obj in objects for v in obj.data.vertices]
    return (Vector(tuple(min(p[i] for p in points) for i in range(3))),
            Vector(tuple(max(p[i] for p in points) for i in range(3))))


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, dimension, metres in MODULES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(SOURCE / SOURCES.get(name, name + ".glb")))
        objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        worlds = {o.name: o.matrix_world.copy() for o in objects}
        for obj in objects:
            world = worlds[obj.name]
            obj.parent = None
            for v in obj.data.vertices:
                v.co = world @ v.co
            obj.matrix_world.identity()
        for obj in list(bpy.context.scene.objects):
            if obj.type != "MESH":
                bpy.data.objects.remove(obj, do_unlink=True)
        low, high = bounds(objects)
        size = high - low
        if dimension == "greenhouse":
            # Long axis, height and span for the supplied frame. The source is
            # a metre-normalized arch, so preserve its proportions explicitly.
            # Blender Y/Z become Godot Z/Y in this asset pipeline. Keep the
            # Godot depth at 8 m and reduce the Godot vertical (source Z).
            scale_vector = Vector((24.0 / size.x, 8.0 / size.y, (8.0 / 3.0) / size.z))
            scale = None
        elif dimension == "crop":
            # These GLBs are already authored at greenhouse metre scale.
            scale = 1.0
            scale_vector = Vector((1.0, 1.0, 1.0))
        else:
            scale = metres / (size.z if dimension == "height" else max(size.x, size.y))
            scale_vector = Vector((scale, scale, scale))
        origin = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
        original = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
        for obj in objects:
            for v in obj.data.vertices:
                v.co = (v.co - origin) * scale_vector
        low, high = bounds(objects)
        for obj in objects:
            for v in obj.data.vertices:
                v.co.z -= low.z
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT / (name + ".glb")),
                                  export_format="GLB", export_apply=True,
                                  export_cameras=False, export_lights=False)
        low, high = bounds(objects)
        size = high - low
        report[name] = {"size_m": [size.x, size.z, size.y],
                        "original_triangles": original,
                        "triangles": sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects)}
        print("TYCHO MODULE", name, report[name], flush=True)
        if name == "l-shape-building":
            # Bake reflection into vertices, reversing face winding with its UV
            # loops. Export recalculates tangent handedness for the normal map.
            # Runtime transforms remain positive, avoiding mirrored-face culling.
            for obj in objects:
                obj.data.transform(Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)))
                obj.data.flip_normals()
                obj.data.update()
            bpy.ops.export_scene.gltf(filepath=str(OUTPUT / "l-shape-building-mirrored.glb"),
                                      export_format="GLB", export_apply=True,
                                      export_cameras=False, export_lights=False)
    (OUTPUT / "modules.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
