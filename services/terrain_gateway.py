"""Small GeoServer WCS/WMS adapter. Run behind the same origin as the game CDN.

Only named sectors from config may be requested. Source rasters stay on GeoServer;
the game receives a 35x35 float height grid (one sample halo) and a 512px orthoimage.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import math
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlencode, urlparse
from urllib.request import urlopen

import numpy as np
import tifffile

TILE_M = 64
STEP_M = 2
GRID = 35  # 33 core vertices + a one-sample halo at each edge


def bounds(sector: dict, x: int, z: int, halo: bool) -> tuple[float, ...]:
    """Godot +X east, +Z south; raster rows north to south.

    WCS TIFF pixels are cell centres. Expand one metre beyond the required
    outer samples, plus the normal halo, to keep shared border samples aligned.
    """
    e, n = sector['origin_easting_m'], sector['origin_northing_m']
    pad = STEP_M * 1.5 if halo else 0
    return e + x * TILE_M - pad, n - (z + 1) * TILE_M - pad, e + (x + 1) * TILE_M + pad, n - z * TILE_M + pad


def fetch(endpoint: str, params: dict) -> bytes:
    with urlopen(endpoint + '?' + urlencode(params), timeout=15) as response:
        data = response.read(16 * 1024 * 1024 + 1)
    if len(data) > 16 * 1024 * 1024:
        raise ValueError('GeoServer response exceeds 16 MiB')
    return data


def make_tile(config: dict, name: str, x: int, z: int) -> bytes:
    sector = config['sectors'][name]
    min_x, min_z, max_x, max_z = sector['tile_bounds']
    if not (min_x <= x <= max_x and min_z <= z <= max_z):
        raise KeyError('outside published sector')
    endpoint = config['geoserver_url'].rstrip('/') + '/ows'
    wcs = dict(service='WCS', version='1.0.0', request='GetCoverage', coverage=sector['dem_layer'],
               crs=sector['crs'], response_crs=sector['crs'], format='GeoTIFF',
               bbox=','.join(map(str, bounds(sector, x, z, True))), width=GRID, height=GRID, interpolation='bilinear')
    dem = np.asarray(tifffile.imread(io.BytesIO(fetch(endpoint, wcs))), dtype=np.float32).squeeze()
    if dem.shape != (GRID, GRID):
        raise ValueError(f'Expected {GRID}x{GRID} single-band DEM, got {dem.shape}')
    nodata = sector.get('nodata', -32768)
    if not np.all(np.isfinite(dem)) or np.any(dem == nodata):
        raise ValueError('DEM contains NoData; keep the offline fallback for this tile')
    dem = dem * sector.get('height_scale_to_m', 1.0) + sector.get('height_offset_m', 0.0) - sector['reference_elevation_m']
    if np.max(np.abs(dem)) > 25000:
        raise ValueError('DEM units or datum are invalid')
    photo = b''
    if sector.get('ortho_layer'):
        wms = dict(service='WMS', version='1.1.1', request='GetMap', layers=sector['ortho_layer'], styles='',
                   srs=sector['crs'], bbox=','.join(map(str, bounds(sector, x, z, False))),
                   width=512, height=512, format='image/png', transparent='false')
        photo = fetch(endpoint, wms)
        if not photo.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('WMS did not return PNG')
    result = dict(version=config['revision'], sector=name, x=x, z=z, grid=GRID, step_m=STEP_M,
                  height_f32=base64.b64encode(dem.astype('<f4').tobytes()).decode(),
                  albedo_png=base64.b64encode(photo).decode())
    return json.dumps(result, separators=(',', ':'), allow_nan=False).encode()


class Gateway(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, config, cache):
        super().__init__(address, Handler)
        self.config = config
        self.cache = cache
        self.cache.mkdir(parents=True, exist_ok=True)
        self.limit = threading.BoundedSemaphore(2)
        self.cache_lock = threading.Lock()

    def prune(self):
        with self.cache_lock:
            files = sorted(self.cache.glob('*.json'), key=lambda p: p.stat().st_mtime)
            total = sum(p.stat().st_size for p in files)
            cap = self.config.get('cache_mb', 512) * 1024 * 1024
            for path in files:
                if total <= cap:
                    break
                total -= path.stat().st_size
                path.unlink()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/health':
            self.send_payload(200, b'{"status":"ok"}')
            return
        match = re.fullmatch(r'/v1/([a-zA-Z0-9_-]+)/([a-z0-9_-]+)/(-?\d+)/(-?\d+)\.json', path)
        if not match:
            self.send_error(404)
            return
        version, name, sx, sz = match.groups()
        config = self.server.config
        if version != config['revision'] or name not in config['sectors']:
            self.send_error(404)
            return
        digest = hashlib.sha256((path + json.dumps(config, sort_keys=True)).encode()).hexdigest()
        target = self.server.cache / (digest + '.json')
        if target.exists():
            self.send_payload(200, target.read_bytes())
            return
        if not self.server.limit.acquire(blocking=False):
            self.send_error(503, 'Terrain worker busy; retry later')
            return
        try:
            payload = make_tile(config, name, int(sx), int(sz))
            with self.server.cache_lock:
                temp = target.with_suffix(f'.{threading.get_ident()}.tmp')
                temp.write_bytes(payload)
                temp.replace(target)
            self.server.prune()
            self.send_payload(200, payload)
        except KeyError:
            self.send_error(404, 'Outside published coverage')
        except Exception as exc:
            self.log_error('GeoServer: %s', exc)
            self.send_error(502, 'Terrain source unavailable')
        finally:
            self.server.limit.release()

    def send_payload(self, code: int, data: bytes):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'public, max-age=86400')
        self.end_headers()
        self.wfile.write(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, default=Path(__file__).with_name('geoserver.example.json'))
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--cache', type=Path, default=Path(__file__).with_name('tile_cache'))
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding='utf-8'))
    server = Gateway(('127.0.0.1', args.port), config, args.cache)
    print(f'Moonwalk terrain gateway: http://127.0.0.1:{args.port}', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
