"""Convert NASA source maps for Godot; preserve LOLA elevations as float32 metres."""
from pathlib import Path
import json
import sys
import importlib.util
from dataclasses import asdict
import numpy as np
import tifffile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'godot/assets/moon'
OUT.mkdir(parents=True, exist_ok=True)
if not (OUT / 'albedo.jpg').exists():
    Image.open(ROOT / 'source_data/lroc_color_poles_4k.tif').convert('RGB').save(OUT / 'albedo.jpg', quality=95)
dem = np.asarray(tifffile.imread(ROOT / 'source_data/ldem_4_uint.tif'), dtype=np.float32) * 0.5 - 10000.0
dem.astype('<f4').tofile(OUT / 'height_m.bin')
(OUT / 'metadata.json').write_text(json.dumps({'width': int(dem.shape[1]), 'height': int(dem.shape[0]), 'radius_m': 1737400, 'min_m': float(dem.min()), 'max_m': float(dem.max()), 'source': 'https://svs.gsfc.nasa.gov/4720', 'layout': 'little-endian float32 metres, row-major north to south, longitude -180 to +180'}, indent=2))
spec = importlib.util.spec_from_file_location('lunar_design', ROOT / 'design/lunar_inpost_strategy/main.py')
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
# Approximate fictional colony coordinates; geography is not specified by the simulation.
coords = [(0, 15), (8.5, 31.4), (32, -16), (-43.3, -11.2), (-82, 30), (-83, 36), (-89.5, 0), (1, -3), (9.6, -20.1), (23.7, -47.4), (8.1, -38), (15, 150), (-25, 155), (-5.9, 179.4)]
locations = []
for (name, loc), (lat, lon) in zip(module.make_locations().items(), coords):
    locations.append(dict(asdict(loc), latitude=lat, longitude=lon))
(OUT / 'colonies.json').write_text(json.dumps({'locations': locations, 'routes': [asdict(r) for r in module.make_routes()], 'coordinates_note': 'Approximate design positions, not canonical or surveyed colony coordinates.'}, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'LOLA: {dem.shape}, {dem.min():.1f}..{dem.max():.1f} m; {len(locations)} colonies exported')
