// Loads a port — a WebAssembly module or the JavaScript one — behind a single
// interface, so the lab and the command-line checker drive every language
// the same way. See spec/ABI.md for the contract.

import { wasiImports } from './wasi.js';

export const SCENES = [
  'STARFIELD', 'TUNNEL', 'PLASMA', 'ROTOZOOM', 'METABALLS',
  'GRID', 'FIRE', 'MANDELBROT', 'FINALE',
];

// fromWasm instantiates a port from its bytes, or from a compiled
// WebAssembly.Module when several instances share one compilation. The
// framebuffer view is rebuilt whenever memory grows, because growing
// detaches the old ArrayBuffer.
export async function fromWasm(source, log) {
  let memory;
  const result = await WebAssembly.instantiate(source, {
    wasi_snapshot_preview1: wasiImports(() => memory, log),
  });
  const instance = result.instance ?? result;
  const ex = instance.exports;
  memory = ex.memory;
  if (ex._initialize) ex._initialize();

  let ptr = 0;
  let len = 0;
  let buf = null;
  let fb = null;
  const pixels = () => {
    if (memory.buffer !== buf) {
      buf = memory.buffer;
      fb = new Uint32Array(buf, ptr, len);
    }
    return fb;
  };
  return {
    init(w, h) {
      ptr = ex.bb_init(w, h) >>> 0;
      len = w * h;
      buf = null;
      return pixels();
    },
    start: (scene) => ex.bb_start(scene),
    // optional: a port without ladders simply has no bb_step
    step: (n) => ex.bb_step?.(n),
    render: (n) => ex.bb_render(n),
    pixels,
  };
}

// fromModule wraps the JavaScript port, whose framebuffer is a plain
// Uint32Array it owns.
export function fromModule(mod) {
  let fb = null;
  return {
    init(w, h) {
      fb = mod.init(w, h);
      return fb;
    },
    start: (scene) => mod.start(scene),
    step: (n) => mod.step?.(n),
    render: (n) => mod.render(n),
    pixels: () => fb,
  };
}
