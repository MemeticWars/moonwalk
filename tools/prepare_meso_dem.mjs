// NASA SVS LOLA 64 px/degree: uncompressed uint16 half-metres, offset -10000 m.
// Offline bake; runtime reads only 512x512 tiles, never the complete TIFF.
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const input = path.join(root, 'source_data/ldem_64_uint.tif');
const out = path.join(root, 'godot/assets/moon/meso');
const fd = fs.openSync(input, 'r');
function read(n, at) { const b = Buffer.alloc(n); if (fs.readSync(fd,b,0,n,at)!==n) throw Error('Incomplete TIFF'); return b; }
const header=read(8,0);
if(header.toString('ascii',0,2)!=='II'||header.readUInt16LE(2)!==42) throw Error('Expected little endian TIFF');
const offset=header.readUInt32LE(4), count=read(2,offset).readUInt16LE();
const entries=read(count*12,offset+2), tags={};
for(let i=0;i<count;i++) {
 const e=entries.subarray(i*12,i*12+12), type=e.readUInt16LE(2), n=e.readUInt32LE(4);
 if(![3,4].includes(type)) continue;
 const size=type===3?2:4, data=n*size<=4?e.subarray(8):read(n*size,e.readUInt32LE(8));
 tags[e.readUInt16LE()]=Array.from({length:n},(_,j)=>size===2?data.readUInt16LE(j*size):data.readUInt32LE(j*size));
}
const w=tags[256][0],h=tags[257][0],rows=tags[278][0],size=512;
if(w!==23040||h!==11520||tags[258][0]!==16||tags[259][0]!==1) throw Error('Unexpected LOLA layout');
fs.mkdirSync(out,{recursive:true});
for(let ty=0;ty<Math.ceil(h/size);ty++) {
 const tiles=Array.from({length:w/size},()=>Buffer.alloc(size*size*2));
 for(let y=0;y<size;y++) {
  const sy=Math.min(h-1,ty*size+y),strip=Math.floor(sy/rows);
  const row=read(w*2,tags[273][strip]+(sy%rows)*w*2);
  for(let tx=0;tx<tiles.length;tx++) row.copy(tiles[tx],y*size*2,tx*size*2,(tx+1)*size*2);
 }
 tiles.forEach((tile,tx)=>fs.writeFileSync(path.join(out,`${tx}_${ty}.bin`),tile));
}
const control_samples=[[0,0],[w-1,h-1],[511,511],[512,512],[10796,8554],[12000,8000]].map(([x,y])=>({x,y,height_m:read(2,tags[273][Math.floor(y/rows)]+((y%rows)*w+x)*2).readUInt16LE()*0.5-10000}));
fs.writeFileSync(path.join(out,'metadata.json'),JSON.stringify({width:w,height:h,tile_size:size,metres_per_pixel_equator:2*Math.PI*1737400/w,scale_m:0.5,offset_m:-10000,source:'https://svs.gsfc.nasa.gov/4720/',credit:'NASA Scientific Visualization Studio / LRO LOLA',layout:'uint16 little endian; north to south, -180 to +180; edge tiles padded',control_samples},null,2));
fs.closeSync(fd);
console.log(`Baked ${Math.ceil(w/size)*Math.ceil(h/size)} LOLA tiles; ${(2*Math.PI*1737400/w).toFixed(2)} m/px`);
