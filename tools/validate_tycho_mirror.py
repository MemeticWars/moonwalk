"""Validate that the reflected L preserves per-corner UVs and embedded textures."""
from pathlib import Path
from collections import Counter
import json, struct, hashlib
ROOT = Path(__file__).resolve().parents[1] / 'godot/assets/colonies/tycho/modules'
def read(name):
 data=(ROOT/name).read_bytes(); length=struct.unpack_from('<I',data,12)[0]
 doc=json.loads(data[20:20+length]); start=20+length
 return doc,data[start+8:]
def accessor(doc, blob, index):
 a=doc['accessors'][index]; v=doc['bufferViews'][a['bufferView']]
 fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']]
 n={'VEC3':3,'VEC2':2,'VEC4':4,'SCALAR':1}[a['type']]
 size=struct.calcsize('<'+fmt*n); offset=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from('<'+fmt*n,blob,offset+i*v.get('byteStride',size)) for i in range(a['count'])]
def corners(doc,blob,reflect):
 result=Counter()
 for mesh in doc['meshes']:
  for p in mesh['primitives']:
   positions=accessor(doc,blob,p['attributes']['POSITION']); uv=accessor(doc,blob,p['attributes']['TEXCOORD_0'])
   for row in accessor(doc,blob,p['indices']):
    i=row[0]; x,y,z=positions[i]
    result[tuple(round(v,4) for v in ((-x if reflect else x),y,z,*uv[i]))]+=1
 return result
def textures(doc,blob):
 result=[]
 for img in doc['images']:
  v=doc['bufferViews'][img['bufferView']]; start=v.get('byteOffset',0)
  result.append(hashlib.sha256(blob[start:start+v['byteLength']]).hexdigest())
 return sorted(result)
a,ab=read('l-shape-building.glb'); b,bb=read('l-shape-building-mirrored.glb')
assert corners(a,ab,True)==corners(b,bb,False), 'Reflected geometry must retain every per-corner UV'
assert textures(a,ab)==textures(b,bb), 'Embedded textures must be unchanged'
print('MIRROR PASS: reflected geometry, per-corner UVs and embedded texture bytes match')
