// Bake a real regional DEM into per-tile height files the game streams locally.
//
//   NODE_PATH=<dir with geotiff installed> node tools/bake_sector_dtm.mjs <ColonyName>
//
// Reads the source GeoTIFF listed in SOURCES below, reprojects it onto the
// colony's local tangent frame (exactly lunar_terrain.latlon_at), and writes
//   godot/assets/sectors/<slug>/<kx>_<kz>.bin   (33x33 float32 LE, z-major)
//   godot/assets/sectors/<slug>/sector.json
// Heights are metres relative to the DEM sample at the colony anchor, matching
// the procedural branch's `elevation(ll) - base_elevation` convention.
//
// Requires: npm i geotiff   (this repo has no package.json; point NODE_PATH at
// an install, e.g. the session scratchpad's node_modules).

import fs from 'fs';
import path from 'path';
import { pathToFileURL } from 'url';

// This repo has no package.json; allow geotiff to live in an external install
// (e.g. a scratch node_modules) via MOONWALK_NODE_MODULES.
const extNM = process.env.MOONWALK_NODE_MODULES;
const geotiffSpec = extNM
  ? pathToFileURL(path.join(extNM, 'geotiff', 'dist-node', 'geotiff.js')).href
  : 'geotiff';
const { fromFile } = await import(geotiffSpec);

const R = 1737400;          // lunar_terrain uses 1737400 m everywhere
const D2R = Math.PI / 180;
const R2D = 180 / Math.PI;
const TILE = 64;            // lunar_terrain.TILE
const STEP = 2;             // lunar_terrain.STEP  -> 33 samples per 64 m tile
const N = TILE / STEP + 1;  // 33
const REPO = process.env.MOONWALK_REPO || 'D:/projects/moonwalk';

// projection: local metres of the sector frame are already near-isometric with
// the source projection's metres, so we go local -> lat/lon -> source (x,y) px.
const SOURCES = {
  'Tycho Station': {
    tiff: 'source_data/dem_real/tycho/NAC_DTM_TYCHOPK.TIF',
    proj: 'eqc', lon0: 348.6, lat1: -43.3,
    radiusTiles: 24,
  },
  'Lubin Deep': {
    tiff: 'source_data/dem_real/south_pole/ldem_87s_5mpp.tif',
    proj: 'stereoS', lon0: 0,
    radiusTiles: 24,
  },
  'Shackleton Ice': {
    tiff: 'source_data/dem_real/south_pole/ldem_87s_5mpp.tif',
    proj: 'stereoS', lon0: 0,
    radiusTiles: 24,
  },
};

function slug(name) { return name.toLowerCase().replaceAll("'", '').replaceAll(' ', '_'); }

function localToLatLon(x, z, aLat, aLon) {
  const lat = aLat - (z / R) * R2D;
  const lon = aLon + (x / (R * Math.cos(aLat * D2R))) * R2D;
  return [lat, lon];
}

function projForward(lat, lon, cfg) {
  if (cfg.proj === 'eqc') {
    let d = lon - cfg.lon0;
    while (d > 180) d -= 360; while (d < -180) d += 360;
    return [R * (d * D2R) * Math.cos(cfg.lat1 * D2R), R * (lat * D2R)];
  }
  // south polar stereographic, sphere, k0=1, natural origin -90, vert lon = lon0
  const phi = lat * D2R;
  const rho = 2 * R * Math.tan(Math.PI / 4 + phi / 2);
  const lam = (lon - cfg.lon0) * D2R;
  return [rho * Math.sin(lam), rho * Math.cos(lam)];
}

const isNodata = (v) => !Number.isFinite(v) || Math.abs(v) > 50000;

async function main() {
  const colony = process.argv[2];
  const cfg = SOURCES[colony];
  if (!cfg) { console.error('Unknown colony. Known:', Object.keys(SOURCES)); process.exit(1); }

  const colonies = JSON.parse(fs.readFileSync(`${REPO}/godot/assets/moon/colonies.json`, 'utf8'));
  const rec = colonies.locations.find((l) => l.name === colony);
  const aLat = rec.latitude, aLon = rec.longitude;
  console.log(`${colony}  anchor ${aLat} / ${aLon}  source ${path.basename(cfg.tiff)}`);

  const tiff = await fromFile(`${REPO}/${cfg.tiff}`);
  const img = await tiff.getImage(0);
  const origin = img.getOrigin();      // top-left corner, projected units
  const res = img.getResolution();     // [dx, dy(<0), 0]
  const W = img.getWidth(), H = img.getHeight();

  // projected (x,y) -> fractional pixel (col,row), pixel centres
  const toPx = (x, y) => [(x - origin[0]) / res[0] - 0.5, (y - origin[1]) / res[1] - 0.5];

  const rt = cfg.radiusTiles;
  const half = rt * TILE + TILE;       // metres from origin to the outer sample
  // pixel bounding box of the whole baked square
  let minC = Infinity, minR = Infinity, maxC = -Infinity, maxR = -Infinity;
  for (const lx of [-half, half]) for (const lz of [-half, half]) {
    const [lat, lon] = localToLatLon(lx, lz, aLat, aLon);
    const [px, py] = projForward(lat, lon, cfg);
    const [c, r] = toPx(px, py);
    minC = Math.min(minC, c); maxC = Math.max(maxC, c);
    minR = Math.min(minR, r); maxR = Math.max(maxR, r);
  }
  const wc0 = Math.floor(minC) - 2, wr0 = Math.floor(minR) - 2;
  const wc1 = Math.ceil(maxC) + 3, wr1 = Math.ceil(maxR) + 3;
  if (wc0 < 0 || wr0 < 0 || wc1 > W || wr1 > H) {
    console.error(`baked square leaves the DEM (px x ${wc0}..${wc1} / ${W}, y ${wr0}..${wr1} / ${H})`);
    console.error('reduce radiusTiles or move the anchor inside the footprint');
    process.exit(1);
  }
  const bw = wc1 - wc0, bh = wr1 - wr0;
  console.log(`reading DEM window ${bw} x ${bh} px (${(bw * bh * 4 / 1e6).toFixed(1)} MB) ...`);
  const raster = await img.readRasters({ window: [wc0, wr0, wc1, wr1] });
  const block = raster[0];
  const sampleBlock = (c, r) => {
    // c,r are full-image fractional pixel coords; bilinear within the window
    const fc = c - wc0, fr = r - wr0;
    const c0 = Math.floor(fc), r0 = Math.floor(fr);
    const c1 = Math.min(c0 + 1, bw - 1), r1 = Math.min(r0 + 1, bh - 1);
    if (c0 < 0 || r0 < 0 || c0 >= bw || r0 >= bh) return NaN;
    const tx = fc - c0, ty = fr - r0;
    const v00 = block[r0 * bw + c0], v10 = block[r0 * bw + c1];
    const v01 = block[r1 * bw + c0], v11 = block[r1 * bw + c1];
    if (isNodata(v00) || isNodata(v10) || isNodata(v01) || isNodata(v11)) {
      // fall back to nearest valid corner
      for (const v of [v00, v10, v01, v11]) if (!isNodata(v)) return v;
      return NaN;
    }
    return (v00 + (v10 - v00) * tx) * (1 - ty) + (v01 + (v11 - v01) * tx) * ty;
  };

  const sampleLocal = (lx, lz) => {
    const [lat, lon] = localToLatLon(lx, lz, aLat, aLon);
    const [px, py] = projForward(lat, lon, cfg);
    const [c, r] = toPx(px, py);
    return sampleBlock(c, r);
  };

  const anchorH = sampleLocal(0, 0);
  if (isNodata(anchorH)) { console.error('anchor sample is nodata'); process.exit(1); }
  console.log(`anchor DEM elevation ${anchorH.toFixed(1)} m (subtracted from every tile)`);

  const dir = `${REPO}/godot/assets/sectors/${slug(colony)}`;
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });

  let written = 0, skipped = 0, ndTotal = 0, lo = Infinity, hi = -Infinity;
  for (let kz = -rt; kz <= rt; kz++) {
    for (let kx = -rt; kx <= rt; kx++) {
      const buf = Buffer.alloc(N * N * 4);
      let nd = 0;
      for (let iz = 0; iz < N; iz++) {
        for (let ix = 0; ix < N; ix++) {
          const lx = kx * TILE + ix * STEP;
          const lz = kz * TILE + iz * STEP;
          let v = sampleLocal(lx, lz);
          if (isNodata(v)) { nd++; v = anchorH; }
          const h = v - anchorH;
          if (h < lo) lo = h; if (h > hi) hi = h;
          buf.writeFloatLE(h, (iz * N + ix) * 4);
        }
      }
      if (nd > N * N * 0.2) { skipped++; ndTotal += nd; continue; }
      ndTotal += nd;
      fs.writeFileSync(`${dir}/${kx}_${kz}.bin`, buf);
      written++;
    }
  }

  const meta = {
    colony, slug: slug(colony), anchor_lat: aLat, anchor_lon: aLon,
    source: path.basename(cfg.tiff), projection: cfg.proj,
    proj_params: cfg.proj === 'eqc' ? { lon0: cfg.lon0, lat1: cfg.lat1 } : { lon0: cfg.lon0, origin_lat: -90 },
    sphere_radius_m: R, grid: N, step_m: STEP, tile_m: TILE,
    tile_key_range: [-rt, rt], anchor_dem_elevation_m: Number(anchorH.toFixed(2)),
    relief_min_m: Number(lo.toFixed(2)), relief_max_m: Number(hi.toFixed(2)),
    nodata_samples: ndTotal, tiles_written: written, tiles_skipped_nodata: skipped,
    baked: new Date().toISOString(),
    note: 'Generated by tools/bake_sector_dtm.mjs. Heights are metres relative to the anchor DEM sample.',
  };
  fs.writeFileSync(`${dir}/sector.json`, JSON.stringify(meta, null, 2) + '\n');
  console.log(`wrote ${written} tiles (${skipped} skipped nodata), relief ${lo.toFixed(1)}..${hi.toFixed(1)} m, ${ndTotal} nodata samples`);
  console.log(`-> ${dir}`);
}

main();
