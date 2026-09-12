"""Remove wheel/antenna regions from the UV-preserving HQ proxy body."""
from pathlib import Path
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "godot" / "assets" / "lorry"
HIGH = ASSETS / "lunar_lorry_hq_uv_proxy.glb"
LOW = ASSETS / "lunar_logistics_rover_decimated.glb"
OUTPUT = ASSETS / "lunar_lorry_textured_body.glb"
CUT_NAMES = {"mesh_0", "mesh_5", "mesh_9", "mesh_10", "mesh_6", "mesh_8"}


def scene_bounds(objects):
    pts = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    return Vector((min(p[i] for p in pts) for i in range(3))), Vector((max(p[i] for p in pts) for i in range(3)))


def object_bounds(obj):
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p[i] for p in pts) for i in range(3)))
    hi = Vector((max(p[i] for p in pts) for i in range(3)))
    return lo, hi


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(HIGH))
body = next(o for o in bpy.context.scene.objects if o.type == "MESH")
high_lo, high_hi = scene_bounds([body])
bpy.ops.import_scene.gltf(filepath=str(LOW))
parts = [o for o in bpy.context.scene.objects if o.type == "MESH" and o != body]
low_lo, low_hi = scene_bounds(parts)
factor = max(high_hi - high_lo) / max(low_hi - low_lo)
low_center = (low_lo + low_hi) * 0.5
high_center = (high_lo + high_hi) * 0.5
for part in parts:
    part.matrix_world = Matrix.Translation(high_center) @ Matrix.Scale(factor, 4) @ Matrix.Translation(-low_center) @ part.matrix_world

boxes = []
for part in parts:
    if part.name.lower().split(".")[0] not in CUT_NAMES:
        continue
    lo, hi = object_bounds(part)
    padding = (hi - lo) * 0.12 + Vector((0.015, 0.015, 0.015))
    boxes.append((lo - padding, hi + padding))

mesh = body.data
bm = bmesh.new()
bm.from_mesh(mesh)
world = body.matrix_world
remove = []
for face in bm.faces:
    center = world @ face.calc_center_median()
    if any(all(lo[i] <= center[i] <= hi[i] for i in range(3)) for lo, hi in boxes):
        remove.append(face)
bmesh.ops.delete(bm, geom=remove, context="FACES")
bm.to_mesh(mesh)
bm.free()
for part in parts:
    bpy.data.objects.remove(part, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", use_selection=True, export_materials="EXPORT", export_apply=True, export_yup=True)
print("LORRY TEXTURED BODY PASS", len(mesh.polygons), "faces", len(remove), "removed", OUTPUT.stat().st_size, flush=True)
