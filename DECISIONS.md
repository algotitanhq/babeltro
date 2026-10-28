# Decisions

How babeltro got to v1, decision by decision. Each entry: context, choice,
why, and who decided: **François** (the human who directs the project) or
**Claude** (the Claude Code session that built it, and the agents it
spawned). The prompts behind them are in [`PROMPTS.md`](PROMPTS.md).

v1 was built in one Claude Code session, 2026-10-27 evening to 2026-10-28,
outside ALGOTITAN's usual Paperclip workflow (no issues, no QA reviews): the
history is this file, `PROMPTS.md` and the commits.

## From a Go demo to a lab

### D1 Start from an existing Go demo

- **Context.** A CPU-rendered Go demo with nine scenes and an on-screen HUD
  existed in a sandbox, plus a one-effect port to the Goose language.
- **Choice.** Keep it as the starting point (`go/`), rename the project, and
  port the same scenes to other languages with an identical rendering.
- **Why.** François's interest is the difference between languages
  producing the same image. *François.*

### D2 The name: babeltro

- **Context.** A first name, `rosette` (the Rosetta stone), was rejected:
  François wanted the project's idea mixed with demoscene vocabulary.
- **Choice.** *Babeltro*: Babel (the tower of languages) + "-tro" (intro,
  cracktro). *François, from Claude's shortlist.*

### D3 The rendered image spells the language's name

- **Choice.** The finale's logo and the scroller say the port's language
  (`GO`, `C`, `RUST`…); the project name appears in the window title only.
- **Consequence.** The finale is the one scene that cannot be
  pixel-identical across languages: the logo's size follows the name's
  width, and the card is laid out around it. Every port proves the name is
  the only cause with a build that spells the reference's name. *François.*

### D4 Make it a pedagogical browser lab

- **Context.** François: the goal is pedagogical, "how would each language
  approach the characteristic demoscene effects", ideally visible in a
  browser.
- **Choice.** Every language compiles to WebAssembly (or runs as
  JavaScript, or brings its interpreter compiled to wasm) behind one small
  contract (`spec/ABI.md`); a single web page drives them. *François (goal),
  Claude (architecture).*

### D5 Little text, little scrolling

- **Choice.** One screen per effect, a short paragraph per effect, one or two
  sentences per language and effect (`NOTES.md`). *François*: explicitly
  less text than ALGOTITAN's previous web project.

## Making the pixels identical

### D6 A deterministic reference

- **Context.** The Go demo used `math/rand`; its starfield respawned stars
  from the global, randomly seeded source, so it was not reproducible even
  in Go.
- **Choice.** A portable xorshift32 (`fmath.Rng`) everywhere a random number
  shapes the image; time derived from the frame number at a fixed 60 Hz,
  never from a clock. *Claude.*

### D7 A checker, and the rule it enforces

- **Choice.** `tools/check.mjs` renders any port and the reference frame by
  frame and counts differing pixels. A port is accepted only at 0 differing
  pixels outside the finale, at several sizes and frames, and at every rung
  of every ladder. Claude re-ran it on every port before committing it.
  *Claude.*

### D8 The traps, written down once

- **Choice.** `spec/ABI.md` lists where languages silently disagree: float
  widths, fused multiply-add, float-to-int conversion, integer width and
  wrap-around, evaluation order, the maths library. Each port follows the
  reference on all of them, or documents the measured cost. *Claude.*

### D9 C is the reference, not Go

- **Context.** Go was the reference at first because the effects were
  written in Go. François: "the C must be the reference".
- **Choice.** C (`ports/c`). Go and C are byte-identical, so nothing
  changed in the pixels; the checker compares with C by default
  (`--ref go` still works). *François.*

## The languages

### D10 Which languages, in which order

- **Choice.** C, Rust, JavaScript first (the classic trio), then Zig, then
  C++, AssemblyScript, Python, plus deliberately atypical entries for
  their teaching value and a bit of fun: Perl, SQL, raw WebAssembly text,
  then x86 assembly. TinyGo came from a reviewer's remark (D13). *François
  (the atypical angle: "how do I make a plasma in Perl"), Claude (the list).*

### D11 x86 assembly runs on an emulator

- **Context.** François wanted real assembly; assembly does not run in a
  browser.
- **Options.** x86 on an emulator in wasm; RISC-V on a smaller emulator;
  native ARM64 shown but not live; present the WAT port as "the assembly".
- **Choice.** x86 (NASM, 32-bit, SSE scalar only) on a small 386+SSE
  interpreter written in C and compiled to wasm. SSE, not x87: x87's 80-bit
  intermediates would break pixel identity. *François, from Claude's
  options.*

### D12 Interpreters in wasm for Python, Perl and SQL

- **Choice.** Pyodide (CPython + NumPy), zeroperl (Perl 5.42, fetched and
  checked against a pinned SHA-256 by `ports/perl/fetch.sh`), sql.js
  (SQLite). The pixels are computed by the language itself: no JavaScript
  helper does the maths. *Claude.*

### D13 TinyGo, and saying what the timings measure

- **Context.** A review note: in the lab Go looked 2–5x slower than C or
  Rust, which mostly measures Go's own wasm backend, not the language.
- **Choice.** Add TinyGo, the same Go files compiled through LLVM (1.5–3x
  faster), show native Go's time for scale, and say on screen that the
  timings measure compilers as much as languages. *Claude, approved by
  François.*

### D14 "Raw WebAssembly", not "hand-written"

- **Context.** The WAT port is written directly in WebAssembly text with no
  compiler, which the lab first called "hand-written"; a reader pointed out
  that its author is an AI agent.
- **Choice.** Call it raw WebAssembly (WAT). *François, after a Reddit
  comment.*

## The lab

### D15 Optimisation ladders

- **Choice.** For the plasma, tunnel and Mandelbrot, each port also
  implements the earlier, naive versions (`bb_step`): `sin()` per pixel,
  then a sine table, then per-row tables; any rung can run next to the last
  one with a pixel diff. Each rung is identical across languages. *Claude,
  approved by François.*

### D16 No side-by-side pixel comparison between languages

- **Context.** Two languages running side by side always said "identical",
  which François found useless.
- **Choice.** Remove it; keep reading two languages' code side by side, the
  pixel diff for ladder rungs, and a race that times every language and
  checks it against C once. *François.*

### D17 A home page that shows everything at once

- **Choice.** The nine effects as live, tilted cards around the question
  "How do you make this effect in <language>?", the language cycling, the
  wordmark drawn by the demo's own font code. *François (the idea and its
  tuning), Claude (the build).*

### D18 The full source a click away

- **Choice.** Every excerpt opens the whole file in a drawer, excerpt
  highlighted, with the port's other files listed. *François.*

### D19 Public, on Cloudflare, with link previews

- **Choice.** A static site on a Cloudflare Worker (assets only), public
  from the start, no Access in front (*François*). Every effect has its own
  address and its own preview image, drawn by the C port at build time
  (`tools/og.mjs`), so a shared link always shows a preview. *François
  (the requirement), Claude (the method).*

### D20 Built with AI agents, said openly

- **Choice.** The site and the README say the ports were written by AI
  agents directed by François, and that every port is checked pixel by
  pixel against the reference. *François.*
