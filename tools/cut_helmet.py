"""Open the helmet bottom geometrically, preserving interpolated UVs and normals."""
from pathlib import Path
import json
import struct
import numpy as np

root = Path(__file__).resolve().parents[1] / 'godot/assets/agnes'
raw = (root / 'helmet.glb').read_bytes()
size = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20 + size])
binary = bytearray(raw[28 + size:])
primitive = doc['meshes'][0]['primitives'][0]

def read(index):
    a = doc['accessors'][index]
    v = doc['bufferViews'][a['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[a['type']]
    return np.frombuffer(binary, dtype='<f4' if a['componentType'] == 5126 else '<u4',
                         count=a['count'] * width,
                         offset=v.get('byteOffset', 0) + a.get('byteOffset', 0)).reshape(-1, width).copy()

attributes = primitive['attributes']
packed = np.concatenate([read(attributes[name]) for name in ['POSITION', 'NORMAL', 'TEXCOORD_0']], axis=1)
triangles = read(primitive['indices']).reshape(-1, 3)
out = []
for tri in triangles:
    polygon = list(packed[tri])
    clipped = []
    for i, point in enumerate(polygon):
        previous = polygon[i - 1]
        inside, old_inside = point[1] >= -0.66, previous[1] >= -0.66
        if inside != old_inside:
            t = (-0.66 - previous[1]) / (point[1] - previous[1])
            clipped.append(previous + t * (point - previous))
        if inside:
            clipped.append(point)
    for i in range(1, len(clipped) - 1):
        triangle = np.array([clipped[0], clipped[i], clipped[i + 1]])
        inner = (triangle[:, :3] - [0, .02, -.03]) / [.47, .67, .46]
        if np.all(np.sum(inner * inner, axis=1) < 1):
            continue
        out.extend(triangle)
out = np.asarray(out, dtype='<f4')
out[:, 3:6] /= np.maximum(np.linalg.norm(out[:, 3:6], axis=1, keepdims=True), 1e-8)

def append(values, kind):
    binary.extend(b'\0' * (-len(binary) % 4))
    offset = len(binary)
    data = np.ascontiguousarray(values, dtype='<f4').tobytes()
    binary.extend(data)
    view = len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(data), 'target': 34962})
    accessor = {'bufferView': view, 'componentType': 5126, 'count': len(values), 'type': kind}
    accessor.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
    doc['accessors'].append(accessor)
    return len(doc['accessors']) - 1

primitive['attributes'] = {name: append(out[:, start:end], kind) for name, start, end, kind in
                           [('POSITION', 0, 3, 'VEC3'), ('NORMAL', 3, 6, 'VEC3'), ('TEXCOORD_0', 6, 8, 'VEC2')]}
primitive.pop('indices')
doc['buffers'][0]['byteLength'] = len(binary)
encoded = json.dumps(doc, separators=(',', ':')).encode()
encoded += b' ' * (-len(encoded) % 4)
result = struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary))
result += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
result += struct.pack('<II', len(binary), 0x004E4942) + binary
(root / 'helmet_fitted.glb').write_bytes(result)
assert out[:, 1].min() >= -0.66001
print(f'Helmet cut: {len(triangles)} -> {len(out)//3} triangles; bottom open at y=-0.66')
