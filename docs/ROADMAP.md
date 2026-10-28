# Roadmap

Where babeltro stands, and the work that could come next. Written for
whoever picks it up — a person or an agent.

## What exists

- **The reference** (`go/`): nine effects, a wasm build with the port
  contract (`spec/ABI.md`), and the native demo it started as.
- **Ports**: eleven besides Go — TinyGo, C, C++, Rust, Zig, AssemblyScript,
  hand-written WebAssembly, JavaScript, Python, Perl, SQL — under `ports/`.
  Every effect a port implements is byte-identical to the C reference; the finale differs
  only through the language's name and the layout that follows its width.
- **Ladders**: the plasma, tunnel and Mandelbrot have optimisation steps
  (`bb_step`), identical in every port that has them, rung for rung.
- **The lab** (`web/`): a home page of live cards, then one screen per
  effect — two languages side by side, pixel diff, ladder steps, each
  language's hot loop with a note, and a race across all languages.
- **The checker** (`tools/check.mjs`): any port against the C reference (or `--ref go`), any scene, step,
  size and frame; PNG dumps of the differences.

## Rules any new work keeps

1. A port is correct only when `node tools/check.mjs <lang>` shows 0
   differing pixels outside the finale, at every rung.
2. Port code is idiomatic for its language and reads as teaching material;
   a naive rung is an honest first attempt, never a strawman.
3. Words on screen stay few. Each port's `NOTES.md` holds one or two
   sentences per scene, in the `- **SCENE**: text` shape the lab parses.
4. Everything in the repository is in English.

## Next, roughly in order

- **More ladders**: metaballs (per-ball offsets hoisted, then a bounding
  box per ball), fire (gather vs scatter), rotozoom (incremental stepping
  along a row instead of a multiply per pixel).
- **More languages**: Odin, Nim, Swift (wasm), Lua, Ruby, Fortran, COBOL, a
  GLSL fragment shader as the "cheating with the GPU" entry; the x86 port
  still lacks the finale. Each one needs a
  build script writing `web/public/wasm/<lang>.wasm`, an entry in
  `web/src/content.js`, and a passing checker run.
- **Parallelism chapter**: the native demo's band pool versus what each
  language can do in the browser (wasm threads need COOP/COEP headers and
  shared memory; JavaScript has workers and SharedArrayBuffer).
- **Small fixes**: the finale's tag line overflows at very small widths
  (the home thumbnails show it); the reference's layout would need a width
  cap, applied in every port.
