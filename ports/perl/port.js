// The Perl port: a Perl 5 interpreter compiled to WebAssembly (zeroperl,
// vendored by fetch.sh), running the effects in ./*.pm. See spec/ABI.md for
// the contract and NOTES.md for what Perl makes of it.
//
// The bridge, per frame:
//   1. JS calls the Perl sub bb_render(n).
//   2. Perl computes the frame as a list of 0xAABBGGRR numbers and packs it,
//      pack('V*', …), into one string of w*h little-endian u32: already the
//      byte layout of an ImageData.
//   3. It returns the address of that string's bytes, unpack('L',
//      pack('p', $FB)): Perl's little-known address-of. On wasm32 an address
//      is an offset into the interpreter's linear memory, so JS copies the
//      frame straight out of it into the framebuffer: one memcpy.
// (zeroperl's own string export would not do: it hands back UTF-8, and a
// frame is anything but text.)
// Building the list is the expensive part: the pack and the copy cost about
// a millisecond at 320x180, against a frame of a hundred or more.

import { ZeroPerl, MemoryFileSystem } from './vendor/zeroperl-ts/index.js';

// Literal URLs, so that Vite ships the files with the worker.
const WASM = new URL('./vendor/zeroperl-ts/zeroperl.wasm', import.meta.url);
const SOURCES = {
  'FMath.pm': new URL('./FMath.pm', import.meta.url),
  'Canvas.pm': new URL('./Canvas.pm', import.meta.url),
  'Starfield.pm': new URL('./Starfield.pm', import.meta.url),
  'Tunnel.pm': new URL('./Tunnel.pm', import.meta.url),
  'Plasma.pm': new URL('./Plasma.pm', import.meta.url),
  'Rotozoom.pm': new URL('./Rotozoom.pm', import.meta.url),
  'Metaballs.pm': new URL('./Metaballs.pm', import.meta.url),
  'Grid.pm': new URL('./Grid.pm', import.meta.url),
  'Fire.pm': new URL('./Fire.pm', import.meta.url),
  'Mandelbrot.pm': new URL('./Mandelbrot.pm', import.meta.url),
  'Finale.pm': new URL('./Finale.pm', import.meta.url),
  'babeltro.pl': new URL('./babeltro.pl', import.meta.url),
};


const inNode = typeof process !== 'undefined' && !!process.versions?.node;

async function text(url) {
  if (url.protocol === 'file:') {
    const fs = 'node:fs/promises';
    const { readFile } = await import(/* @vite-ignore */ fs);
    return readFile(url, 'utf8');
  }
  const res = await fetch(url);
  if (!res.ok) throw new Error(`perl: ${url}: ${res.status}`);
  return res.text();
}

let perl = null;
let fb = null;
let bytes = null;
// Every call into Perl is asynchronous (zeroperl is built with Asyncify),
// but the host calls start() and step() without waiting. Chaining every
// call on one promise keeps them in order and never re-enters the
// interpreter.
let queue = Promise.resolve();
const later = (f) => (queue = queue.then(f));

async function call(name, ...args) {
  const vals = args.map((a) => perl.createInt(a));
  try {
    const sv = await perl.call(name, vals, 'scalar');
    const err = perl.getLastError();
    if (err) throw new Error(`perl: ${name}: ${err}`);
    return sv;
  } finally {
    for (const v of vals) v.dispose();
  }
}

export async function load() {
  const out = (stream) => (d) => {
    const s = typeof d === 'string' ? d : new TextDecoder().decode(d);
    if (s.trim()) stream(`[perl] ${s.trimEnd()}`);
  };
  const fileSystem = new MemoryFileSystem({ '/': '' });
  for (const [name, url] of Object.entries(SOURCES)) {
    fileSystem.addFile(`/babeltro/${name}`, await text(url));
  }
  // zeroperl tells the browser from Node by looking for window and document;
  // in a Web Worker it finds neither and would read the wasm with node:fs.
  // Show it a window for the duration of create(), and hand it the bytes.
  const fake = !inNode && typeof window === 'undefined';
  if (fake) {
    globalThis.window = globalThis;
    globalThis.document = {};
  }
  try {
    perl = await ZeroPerl.create({
      fileSystem,
      fetch: () => fetch(WASM),
      stdout: out(console.log),
      stderr: out(console.error),
    });
  } finally {
    if (fake) {
      delete globalThis.window;
      delete globalThis.document;
    }
  }
  const r = await perl.eval(`use lib '/babeltro'; require 'babeltro.pl';`);
  if (!r.success) throw new Error(`perl: ${r.error}`);
}

export function init(w, h) {
  fb = new Uint32Array(w * h);
  bytes = new Uint8Array(fb.buffer);
  later(() => call('bb_init', w, h).then((sv) => sv?.dispose()));
  return fb;
}

export function start(scene) {
  later(() => call('bb_start', scene).then((sv) => sv?.dispose()));
}

export function step(n) {
  later(() => call('bb_step', n).then((sv) => sv?.dispose()));
}

export function render(n) {
  return later(async () => {
    const sv = await call('bb_render', n);
    const ptr = sv.toInt() >>> 0;
    sv.dispose();
    bytes.set(new Uint8Array(perl.exports.memory.buffer, ptr, bytes.length));
  });
}

export const framebuffer = () => fb;
