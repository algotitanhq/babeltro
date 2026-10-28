// The Python port: CPython and NumPy compiled to wasm (Pyodide), running the
// effects in ports/python/*.py. This module is the glue the lab and
// tools/check.mjs drive (spec/ABI.md, "a port that runs as JavaScript").
//
// Where Pyodide comes from:
//   Node (tools/check.mjs)   the npm package pinned in package.json, from
//                            ports/python/node_modules. NumPy is not in the
//                            npm package: the first run fetches its wheel
//                            from the CDN below and caches it next to it.
//   Browser (web/src/worker) the official jsdelivr CDN build of the same
//                            version. Bundling the 10 MB interpreter into the
//                            lab would gain nothing: the CDN serves it
//                            compressed and cached across sites.
// Both specifiers are computed, so Vite leaves them alone.

const PYODIDE_VERSION = '314.0.7'; // keep in step with package.json
const CDN = `https://cdn.jsdelivr.net/pyodide/v${PYODIDE_VERSION}/full/`;

// The effects, loaded into Pyodide's file system as plain modules.
const SOURCES = [
  'fmath', 'palette', 'canvas', 'babeltro',
  'starfield', 'tunnel', 'plasma', 'rotozoom', 'metaballs',
  'grid', 'fire', 'mandelbrot', 'finale',
];

export const scenes = [0, 1, 2, 3, 4, 5, 6, 7, 8];

const isNode = typeof process !== 'undefined' && !!process.versions?.node;

let py = null; // the Pyodide instance
let bb = null; // the babeltro Python module
let fbProxy = null; // the NumPy framebuffer, as a PyProxy
let fbBuffer = null; // a PyBuffer over it
let pixels = null; // the Uint32Array the host reads
let renderPy = null;

// Read in Node, fetched in the browser: Vite turns this `new URL` into an
// asset for each ./*.py file.
async function source(name) {
  const url = new URL(`./${name}.py`, import.meta.url);
  if (isNode) {
    const fs = 'node:fs/promises';
    return (await import(/* @vite-ignore */ fs)).readFile(url, 'utf8');
  }
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${name}.py: ${res.status}`);
  return res.text();
}

export async function load() {
  const quiet = () => {};
  let loadPyodide;
  if (isNode) {
    const spec = 'pyodide';
    ({ loadPyodide } = await import(/* @vite-ignore */ spec));
    py = await loadPyodide({ stdout: quiet }); // indexURL: the package's own directory
  } else {
    ({ loadPyodide } = await import(/* @vite-ignore */ `${CDN}pyodide.mjs`));
    py = await loadPyodide({ indexURL: CDN, stdout: quiet });
  }
  if (py.version !== PYODIDE_VERSION) throw new Error(`Pyodide ${py.version}, expected ${PYODIDE_VERSION}`);
  await py.loadPackage('numpy', { messageCallback: quiet });

  const dir = '/home/pyodide/babeltro';
  py.FS.mkdirTree(dir);
  const texts = await Promise.all(SOURCES.map(source));
  SOURCES.forEach((name, i) => py.FS.writeFile(`${dir}/${name}.py`, texts[i]));
  py.runPython(`import sys; sys.path.insert(0, ${JSON.stringify(dir)})`);
  bb = py.pyimport('babeltro');
  renderPy = bb.render;
  const have = [...bb.SCENES.keys()].sort((a, b) => a - b).join();
  if (have !== scenes.join()) throw new Error(`port.js lists scenes ${scenes}, babeltro.py has ${have}`);
}

// The framebuffer bridge. Python owns the pixels: babeltro.init allocates an
// (h, w) uint32 NumPy array, and every effect writes into it in place. Its
// data lives in Pyodide's wasm memory, so getBuffer() hands back a
// Uint32Array *view* of those bytes: no copy, no Python objects per frame,
// nothing crosses the boundary but the call to render(n). The one catch is
// that when the wasm memory grows, every view of the old ArrayBuffer is
// detached (its length drops to 0). The array itself has not moved, so
// framebuffer() simply asks for a fresh view whenever that happens.
function view() {
  if (!pixels || pixels.length === 0) {
    fbBuffer?.release();
    fbBuffer = fbProxy.getBuffer('u32');
    pixels = fbBuffer.data;
  }
  return pixels;
}

export function init(w, h) {
  fbBuffer?.release();
  fbBuffer = null;
  fbProxy?.destroy();
  fbProxy = bb.init(w, h);
  pixels = null;
  return view();
}

export function start(scene) {
  bb.start(scene);
}

export function step(n) {
  bb.step(n);
}

export function render(n) {
  renderPy(n);
}

export function framebuffer() {
  return view();
}
