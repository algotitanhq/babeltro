// The SQL port: every pixel is computed by SQLite, compiled to WebAssembly
// by sql.js. This file only moves data in and out of the database: it binds
// the size and the frame number, runs the scene's prepared statements, and
// copies the single blob the last one returns into the framebuffer. No
// JavaScript function is registered with SQLite; the maths is SQL.
//
// Each scene is a .sql file cut into sections by `-- @run <name>` lines:
//   resize    run when the scene starts at a new size (Go's Resize)
//   start     run every time the scene starts (fresh state)
//   rung      run when rung 0 (the default) is chosen; `rung/<k>` for rung k
//   frame     prepared once, run for every frame; `frame/<k>`, if there is
//             one, replaces it on rung k of the scene's ladder
// A frame section may hold several statements (the fire updates its state
// table first); the last one returns one row, one column: the frame, as a
// w*h*4-byte blob of R, G, B, A bytes.

import initSqlJs from 'sql.js';

// Files next to this module, found the same way in Node and in the browser:
// `new URL(path, import.meta.url)` is a file: URL under Node, and Vite turns
// it into the URL of an emitted asset when it bundles the lab's worker.
const FILES = {
  tables: new URL('./tables.sql', import.meta.url),
  1: new URL('./tunnel.sql', import.meta.url),
  2: new URL('./plasma.sql', import.meta.url),
  6: new URL('./fire.sql', import.meta.url),
  7: new URL('./mandelbrot.sql', import.meta.url),
};
// sql.js ships sql-wasm.wasm for Node and sql-wasm-browser.wasm for
// bundlers; the two files are byte-identical (1.14.2), so one serves both.
const WASM = new URL('./node_modules/sql.js/dist/sql-wasm.wasm', import.meta.url);

const isNode = WASM.protocol === 'file:';
// a variable specifier keeps bundlers from trying to package Node's fs
const nodeFs = 'node:fs/promises';
const nodeUrl = 'node:url';

async function text(url) {
  if (isNode) return (await import(/* @vite-ignore */ nodeFs)).readFile(url, 'utf8');
  return (await fetch(url)).text();
}

export const scenes = [1, 2, 6, 7];

let db = null;
const sources = {};
let w = 0;
let h = 0;
let fb = null;
let bytes = null;
let scene = -1;
let rung = 0;
let statements = [];
const sizedAt = {}; // the size each scene's resize section last ran for

export async function load() {
  // locateFile tells sql.js where its .wasm is: a file path under Node
  // (Emscripten reads it with fs), a URL in the browser (it fetches it).
  const wasmPath = isNode ? (await import(/* @vite-ignore */ nodeUrl)).fileURLToPath(WASM) : WASM.href;
  const SQL = await initSqlJs({ locateFile: () => wasmPath });
  db = new SQL.Database();
  const entries = await Promise.all(Object.entries(FILES).map(async ([k, url]) => [k, await text(url)]));
  for (const [k, src] of entries) sources[k] = sections(src);
  db.exec(sources.tables.all);
  db.exec('CREATE TABLE size (w INTEGER, h INTEGER)');
}

// sections splits a scene file at its `-- @run <name>` lines.
function sections(src) {
  const out = { all: src };
  const parts = src.split(/^-- @run (\S+)[^\n]*\n/m);
  for (let i = 1; i < parts.length; i += 2) out[parts[i]] = parts[i + 1];
  return out;
}

export function init(width, height) {
  w = width;
  h = height;
  fb = new Uint32Array(w * h);
  bytes = new Uint8Array(fb.buffer);
  db.run('DELETE FROM size');
  db.run('INSERT INTO size VALUES (?, ?)', [w, h]);
  scene = -1;
  return fb;
}

export function start(s) {
  scene = s;
  rung = 0;
  const src = sources[s];
  if (!src) return;
  if (src.resize && sizedAt[s] !== `${w}x${h}`) {
    db.exec(src.resize);
    sizedAt[s] = `${w}x${h}`;
  }
  if (src.start) db.exec(src.start);
  step(0);
}

export function step(n) {
  for (const st of statements) st.free();
  statements = [];
  rung = n;
  const src = sources[scene];
  if (!src) return;
  const setup = src[`rung/${rung}`] ?? src.rung;
  if (setup) db.exec(setup);
  const sql = src[`frame/${rung}`] ?? src.frame;
  // sql.js splits the section into statements (and frees each one as it
  // moves on), so keep their text and prepare them for good
  const texts = [];
  for (const st of db.iterateStatements(sql)) texts.push(st.getSQL());
  statements = texts.map((t) => db.prepare(t));
}

export function render(n) {
  let blob = null;
  for (const st of statements) {
    st.bind({ ':n': n });
    if (st.step()) blob = st.get()[0];
    st.reset();
  }
  if (blob) bytes.set(blob);
}
