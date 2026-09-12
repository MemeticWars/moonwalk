"""Separate rigid backpack and reduce head size in copies of the six suit GLBs."""
from pathlib import Path
import json
import struct
import numpy as np

ROOT = Path(__file__).resolve().parents[1] / 'godot/assets/agnes'
OUT = ROOT / 'fitted'
OUT.mkdir(exist_ok=True)

def fit(source):
    raw = source.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + size])
    binary = bytearray(raw[28 + size:])
    def read(index):
        a = doc['accessors'][index]
        v = doc['bufferViews'][a['bufferView']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        return np.frombuffer(binary, dtype={5126:'<f4',5123:'<u2',5125:'<u4',5121:'u1'}[a['componentType']],
                             count=a['count'] * width, offset=v.get('byteOffset',0) + a.get('byteOffset',0)).reshape(-1,width).copy()
    def append(values, kind, integer=False):
        binary.extend(b'\0' * (-len(binary) % 4))
        offset = len(binary)
        binary.extend(np.ascontiguousarray(values, dtype='<u4' if integer else '<f4').tobytes())
        doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset})
        item = {'bufferView':len(doc['bufferViews'])-1,'componentType':5125 if integer else 5126,'count':len(values),'type':kind}
        if kind == 'VEC3': item.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        doc['accessors'].append(item)
        return len(doc['accessors'])-1
    def write(index, values):
        """Replace an existing float accessor in the GLB binary."""
        a = doc['accessors'][index]
        assert a['componentType'] == 5126
        v = doc['bufferViews'][a['bufferView']]
        offset = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        data = np.ascontiguousarray(values, dtype='<f4').tobytes()
        binary[offset:offset + len(data)] = data
    primitive = doc['meshes'][0]['primitives'][0]
    attrs = primitive['attributes']
    positions, normals, uv = (read(attrs[name]) for name in ['POSITION','NORMAL','TEXCOORD_0'])
    joints, weights = read(attrs['JOINTS_0']), read(attrs['WEIGHTS_0'])
    triangles = read(primitive['indices']).reshape(-1,3)
    skin = doc['skins'][0]
    names = [doc['nodes'][i]['name'] for i in skin['joints']]
    inverse_bind = read(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    head_center = np.linalg.inv(inverse_bind[names.index('Head')])[:3,3]
    head_indices = [i for i,name in enumerate(names) if name in ['Head','head_end','headfront']]
    amount = np.sum(weights * np.isin(joints,head_indices), axis=1)
    fitted = positions + (head_center - positions) * (amount[:,None] * 0.10)
    # Spear Walk brings the thighs too close together. The rig uses centimetres
    # before its 0.01 Armature scale, so 3.0 here is a 3 cm outward shift per leg.
    # Keep every downstream bone parented to its thigh: knees and boots follow
    # rigidly and the animation's original rotations remain intact.
    widened_walk = source.name == 'agnes_suit_Animation_Spear_Walk_withSkin.glb'
    if widened_walk:
        for animation in doc.get('animations', []):
            for channel in animation['channels']:
                node = doc['nodes'][channel['target']['node']]['name']
                if node not in ['LeftUpLeg', 'RightUpLeg', 'LeftFoot', 'RightFoot'] or channel['target']['path'] != 'translation':
                    continue
                output = animation['samplers'][channel['sampler']]['output']
                values = read(output)
                direction = 1.0 if node in ['LeftUpLeg', 'LeftFoot'] else -1.0
                # A smaller offset at the ankle clears boots at the crossing
                # phase without making the gait bow-legged.
                values[:, 0] += direction * (3.0 if 'UpLeg' in node else 1.5)
                write(output, values)
    center = positions[triangles].mean(axis=1)
    backpack = (center[:,2] < -0.11) & (center[:,1] > 0.935) & (np.abs(center[:,0]) < 0.21)
    assert 1000 < backpack.sum() < len(triangles) * .3
    primitive['indices'] = append(triangles[~backpack].reshape(-1,1), 'SCALAR', True)
    primitive['attributes']['POSITION'] = append(fitted, 'VEC3')
    indices, remap = np.unique(triangles[backpack].reshape(-1), return_inverse=True)
    chest = names.index('Spine02')
    transform = inverse_bind[chest]
    points = (np.column_stack((positions[indices],np.ones(len(indices)))) @ transform.T)[:,:3]
    rigid_normals = normals[indices] @ np.linalg.inv(transform[:3,:3])
    rigid_normals /= np.linalg.norm(rigid_normals,axis=1,keepdims=True)
    rigid = {'attributes':{'POSITION':append(points,'VEC3'),'NORMAL':append(rigid_normals,'VEC3'),
                           'TEXCOORD_0':append(uv[indices],'VEC2')},
             'indices':append(remap.reshape(-1,1),'SCALAR',True), 'material':primitive['material']}
    doc['meshes'].append({'name':'RigidBackpack','primitives':[rigid]})
    doc['nodes'].append({'name':'RigidBackpack','mesh':len(doc['meshes'])-1})
    doc['nodes'][skin['joints'][chest]].setdefault('children',[]).append(len(doc['nodes'])-1)
    for image in doc.get('images',[]): image['uri'] = '../' + image['uri']
    doc['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(doc,separators=(',',':')).encode()
    encoded += b' ' * (-len(encoded)%4)
    result = struct.pack('<III',0x46546C67,2,28+len(encoded)+len(binary))
    result += struct.pack('<II',len(encoded),0x4E4F534A)+encoded
    result += struct.pack('<II',len(binary),0x004E4942)+binary
    (OUT/source.name).write_bytes(result)
    assert 'JOINTS_0' not in rigid['attributes'] and 'skin' not in doc['nodes'][-1]
    suffix = '; walk thighs +3 cm, feet +1.5 cm outward' if widened_walk else ''
    print(source.name, ': rigid backpack',int(backpack.sum()),'triangles; head scale 90%' + suffix)

for source in sorted(ROOT.glob('*suit*.glb')):
    fit(source)
