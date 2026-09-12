"""Copy suit animations with shared external textures; leave source GLBs intact."""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'godot/assets/agnes'
OUT.mkdir(parents=True, exist_ok=True)
sources = sorted((ROOT / 'artifacts/sprites/agnes').glob('*suit*.glb'))
sources.append(ROOT / 'artifacts/sprites/agnes/helmet.glb')
for source in sources:
    raw = source.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    binary = raw[28 + length:]
    for image in doc.get('images', []):
        view = doc['bufferViews'][image.pop('bufferView')]
        start = view.get('byteOffset', 0)
        data = binary[start:start + view['byteLength']]
        suffix = '.jpg' if image.get('mimeType') == 'image/jpeg' else '.png'
        prefix = 'helmet_' if source.stem == 'helmet' else 'suit_'
        name = prefix + hashlib.sha256(data).hexdigest()[:12] + suffix
        (OUT / name).write_bytes(data)
        image.pop('mimeType', None)
        image['uri'] = name
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    result = struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary))
    result += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
    result += struct.pack('<II', len(binary), 0x004E4942) + binary
    (OUT / source.name).write_bytes(result)
    print(source.name, '->', name)
