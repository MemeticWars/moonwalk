"""Build the freight-truck GLB from two separate Meshy exports of the same
Lunar Logistics Rover: a single fully-textured hull (no separable parts) and
an untextured part-segmentation pass whose 8 wheels are individually
separable. The textured hull's own wheel bulges are fused to the body mesh
(one connected surface even after welding coincident vertices), so they are
kept as-is and the segmented wheels are scaled/placed on top of them rather
than cut out -- a plain, slightly-larger tire fully covers the bulge underneath.
"""
from pathlib import Path
import bpy
from mathutils import Vector, Matrix

root = Path(__file__).resolve().parents[1]
body_source = root / "artifacts/sprites/track/Meshy_AI_Lunar_Logistics_Rover_0908201853_texture.glb"
wheels_source = root / "artifacts/sprites/track/Meshy_AI_Lunar Logistics Rover_1788897764_part-segmentation.glb"
output = root / "godot/assets/lorry/lunar_logistics_rover_full.glb"


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_bounds(objs):
    low = high = None
    for o in objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            if low is None:
                low, high = Vector(p), Vector(p)
            else:
                low = Vector((min(low[i], p[i]) for i in range(3)))
                high = Vector((max(high[i], p[i]) for i in range(3)))
    return low, high


def bake_transform(obj, transform):
    world = obj.matrix_world.copy()
    for v in obj.data.vertices:
        v.co = transform(world @ v.co)
    obj.matrix_world = Matrix.Identity(4)


bpy.ops.wm.read_factory_settings(use_empty=True)

# --- Body: the single textured hull, kept exactly as authored.
bpy.ops.import_scene.gltf(filepath=str(body_source))
body_objs = mesh_objects()
for o in body_objs:
    o.name = "body"
body_low, body_high = world_bounds(body_objs)

# --- Wheels: donor part-segmentation pass. mesh_0/mesh_9 there are its own
# two chassis/hull parts (the textured body above already covers that role);
# the other 8 are individually separable wheels. The *whole donor* bbox (all
# 10 parts) is what is comparable to the textured body's bbox -- the 8 wheels
# alone only span the vehicle's footprint in X/Y, not its Z (roof) height, so
# scaling from a wheels-only bbox would blow Z out of proportion.
bpy.ops.import_scene.gltf(filepath=str(wheels_source))
donor_objs = [o for o in mesh_objects() if o not in body_objs]
donor_low, donor_high = world_bounds(donor_objs)
donor_size = donor_high - donor_low
for o in list(donor_objs):
    if o.name in ("mesh_0", "mesh_9"):
        bpy.data.objects.remove(o, do_unlink=True)
        donor_objs.remove(o)
assert len(donor_objs) == 8, f"expected 8 donor wheel meshes, found {len(donor_objs)}: {[o.name for o in donor_objs]}"

body_size = body_high - body_low
# Both exports are the same vehicle at consistent but different absolute
# scales (~15.76x apart on all three axes independently -- verified before
# writing this script, not assumed), so one uniform factor carries wheel
# geometry into the body's frame without distorting the wheel discs.
scale = sum(body_size[i] / donor_size[i] for i in range(3)) / 3.0
# Horizontally both exports are centred on their own vehicle at (0, 0); the
# donor's vertical zero is its own ground/wheel-contact plane (verified
# low.z == 0.0 for its overall bounds), while the body's zero is its volume
# centroid -- align the two ground planes instead of assuming a shared origin.
z_offset = body_low.z - donor_low.z * scale

tire_mat = bpy.data.materials.new("TireRubber")
tire_mat.use_nodes = True
bsdf = tire_mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.035, 0.032, 0.03, 1.0)
bsdf.inputs["Roughness"].default_value = 0.92

for i, o in enumerate(sorted(donor_objs, key=lambda o: o.name)):
    bake_transform(o, lambda p, s=scale, dz=z_offset: Vector((p.x * s, p.y * s, p.z * s + dz)))
    o.name = f"wheel_{i}"
    o.data.materials.clear()
    o.data.materials.append(tire_mat)

wheel_objs = [o for o in mesh_objects() if o not in body_objs]
final_low, final_high = world_bounds(body_objs + wheel_objs)
print("BODY size", tuple(body_size), "DONOR (whole) size", tuple(donor_size), "SCALE", scale, "Z_OFFSET", z_offset)
print("FINAL combined bbox", tuple(final_high - final_low))
for o in wheel_objs:
    lo, hi = world_bounds([o])
    print(" ", o.name, "center", tuple((lo + hi) * 0.5), "bbox", tuple(hi - lo))

output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", export_apply=True, export_cameras=False, export_lights=False)
print("WROTE", output)
