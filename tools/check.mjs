#!/usr/bin/env node
// check compares ports against the Go reference, frame by frame, and times
// them. It drives the same host code as the browser lab.
//
//   node tools/check.mjs c rust js                 every scene, default frames
//   node tools/check.mjs --scene 2 --at 1,30 c      one scene, chosen frames
//   node tools/check.mjs --png /tmp/out c           also write ref/port/diff PNGs
//   node tools/check.mjs --scene 2 --step 1 c       one rung of a scene's ladder
//   node tools/check.mjs --scene 2 --step 1 --ref-step 3 go
//                                                   a rung against the optimised one
//
// A port is ports/<lang>/port.js if that exists (JavaScript-hosted), else
// web/public/wasm/<lang>.wasm. A port that lists its `scenes` is checked on
// those only.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { SCENES, fromWasm, fromModule } from '../web/src/host/ports.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const args = process.argv.slice(2);
const opt = { size: '640x360', at: '1,2,60,300', scene: null, step: '0', png: null };
const langs = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a.startsWith('--')) opt[a.slice(2)] = args[++i];
  else langs.push(a);
}
if (langs.length === 0) {
  console.error('usage: check.mjs [--size WxH] [--at n,n,…] [--scene i] [--png dir] lang…');
  process.exit(2);
}
const [W, H] = opt.size.split('x').map(Number);
const checkpoints = opt.at.split(',').map(Number).sort((a, b) => a - b);
const last = checkpoints[checkpoints.length - 1];
const step = Number(opt.step);
const refStep = opt['ref-step'] === undefined ? step : Number(opt['ref-step']);
const scenes = opt.scene === null ? SCENES.map((_, i) => i) : [Number(opt.scene)];

async function load(lang) {
  const modPath = join(root, 'ports', lang, 'port.js');
  if (existsSync(modPath)) return fromModule(await import(pathToFileURL(modPath).href));
  const bytes = readFileSync(join(root, 'web/public/wasm', `${lang}.wasm`));
  return fromWasm(bytes, (line) => console.error(`[${lang}] ${line}`));
}

function png(path, rgba) {
  const crcTab = new Int32Array(256).map((_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c;
  });
  const crc = (buf) => {
    let c = -1;
    for (const b of buf) c = crcTab[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ -1) >>> 0;
  };
  const chunk = (type, data) => {
    const out = Buffer.alloc(12 + data.length);
    out.writeUInt32BE(data.length, 0);
    out.write(type, 4, 'ascii');
    data.copy(out, 8);
    out.writeUInt32BE(crc(out.subarray(4, 8 + data.length)), 8 + data.length);
    return out;
  };
  const hdr = Buffer.alloc(13);
  hdr.writeUInt32BE(W, 0);
  hdr.writeUInt32BE(H, 4);
  hdr[8] = 8;
  hdr[9] = 6;
  const raw = Buffer.alloc((W * 4 + 1) * H);
  const src = Buffer.from(rgba.buffer, rgba.byteOffset, W * H * 4);
  for (let y = 0; y < H; y++) src.copy(raw, y * (W * 4 + 1) + 1, y * W * 4, (y + 1) * W * 4);
  writeFileSync(path, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', hdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]));
}

// compare counts differing pixels, the largest channel difference and the
// bounding box of the differences.
function compare(a, b) {
  let n = 0, max = 0, x0 = W, y0 = H, x1 = -1, y1 = -1;
  for (let i = 0; i < a.length; i++) {
    const p = a[i], q = b[i];
    if (p === q) continue;
    n++;
    for (let s = 0; s < 24; s += 8) {
      const d = Math.abs(((p >>> s) & 255) - ((q >>> s) & 255));
      if (d > max) max = d;
    }
    const x = i % W, y = (i / W) | 0;
    if (x < x0) x0 = x;
    if (x > x1) x1 = x;
    if (y < y0) y0 = y;
    if (y > y1) y1 = y;
  }
  return { n, max, box: n ? `${x0},${y0}-${x1},${y1}` : '' };
}

const median = (xs) => [...xs].sort((a, b) => a - b)[xs.length >> 1];

const ref = await load('go');
ref.init(W, H);
const ports = [];
for (const lang of langs) {
  const p = await load(lang);
  p.init(W, H);
  ports.push({ lang, p });
}
if (opt.png) mkdirSync(opt.png, { recursive: true });

console.log(`${W}x${H}, frames ${checkpoints.join(',')}, step ${step}, reference go step ${refStep}\n`);
console.log('lang  scene        frame   diff px   max  box                 go ms   port ms');
let failed = 0;
for (const { lang, p } of ports) {
  for (const s of scenes) {
    if (p.scenes && !p.scenes.includes(s)) continue;
    ref.start(s);
    p.start(s);
    ref.step(refStep);
    p.step(step);
    const tRef = [], tPort = [];
    for (let n = 1; n <= last; n++) {
      let t = performance.now();
      ref.render(n);
      tRef.push(performance.now() - t);
      t = performance.now();
      await p.render(n);
      tPort.push(performance.now() - t);
      if (!checkpoints.includes(n)) continue;
      const a = ref.pixels(), b = p.pixels();
      const r = compare(a, b);
      if (r.n) failed++;
      const ms = n === last ? `${median(tRef).toFixed(2).padStart(7)} ${median(tPort).toFixed(2).padStart(9)}` : '';
      console.log(`${lang.padEnd(5)} ${SCENES[s].padEnd(12)} ${String(n).padStart(5)} ${String(r.n).padStart(9)} ${String(r.max).padStart(5)}  ${r.box.padEnd(18)} ${ms}`);
      if (opt.png && r.n) {
        const base = join(opt.png, `${lang}_${s}_${SCENES[s]}_${n}`);
        png(`${base}_go.png`, a);
        png(`${base}_${lang}.png`, b);
        const d = new Uint32Array(W * H);
        for (let i = 0; i < d.length; i++) d[i] = a[i] === b[i] ? 0xff202020 : 0xff0000ff;
        png(`${base}_diff.png`, d);
      }
    }
  }
}
process.exitCode = failed ? 1 : 0;
