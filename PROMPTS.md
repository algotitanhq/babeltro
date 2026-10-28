# Prompts

How babeltro was made, in the words that made it. François directed a
Claude Code session (Claude Opus); that session wrote the lab, the checker
and the reference changes itself, and spawned one AI agent per port. Every
port was then re-checked by the session before it was committed.

Part 1 is François's prompts, in order, translated from French (lightly
condensed; remarks about other projects and budget left out). Part 2 is
what each port agent was asked to do, condensed from the briefs. The why of
each choice is in [`DECISIONS.md`](DECISIONS.md).

## Part 1 · François's prompts

1. Rename this project draft with an evocative name, move it to `projects`,
   create a private remote repo. It's a personal, experimental project. I'd
   like you to port this demo to other languages with an identical
   rendering; the differences between languages to produce the same thing
   are what interests me. Which languages would you pick first?
2. "rosette" doesn't work, pick another name and rename. And yes, change the
   text in the demo too: show the language's name. Then OK to start with C.
   Does this project make sense, or am I burning tokens for nothing?
3. A mix between the project's idea and the demoscene aesthetic. *(→ babeltro)*
4. Do everything in English, docs included; only between us do we speak
   French.
5. I'd like to reorient the project. These nine scenes are very
   characteristic demoscene effects. The idea is really pedagogical: with
   this or that language, what would be the possible approaches to create
   the characteristic demoscene effects. Ideally we can see it in a
   browser — maybe each language through WebAssembly. Keep the pedagogical
   aspect above all.
6. Go, JS, C and Rust. English only, but don't generate too much text: it
   should stay digestible and above all pleasant to test, compare and
   drive, with as little scrolling as possible unless justified.
7. I don't understand the milliseconds under the demos, nor the compare and
   differences options. The syntax highlighting looks the same for every
   language. The home page lands on the plasma directly: it could show the
   nine effects as cards, scattered, with the central question: in each
   language, how do I make this effect? Otherwise continue the plan; don't
   limit yourself.
8. Put the BABELTRO logo big on the home page, tilted or straight, above the
   question, and cycle the language names faster: there will be many more
   languages. Then some atypical ones: something like how do I make a
   plasma in Perl — a bit silly, but very interesting, and it will make
   people laugh.
9. Pull the cards closer to the centre and cycle the names faster, so that
   arriving on the site is a "wow". Add a few languages.
10. Perl shows black and SQL is greyed. Put it on Cloudflare. Why is Go the
    reference? The reference should be something like assembly or C. And
    assembly is missing. And is the comparison feature worth keeping? You
    can't compare anything with it.
11. *(on the assembly options)* x86, live.
12. Don't put Access in front; it goes public right away.
13. There are still texts saying everything was done against Go: C must be
    the reference. We only see the excerpt for each language: we should be
    able to open the whole source to see its context, in a panel or
    something smart.
14. I don't understand the optimisation steps field.
15. Finish the assembly part, and put a link to GitHub somewhere, consistent.
    Then only the GitHub logo in the header.
16. On mobile only four effects show on the home page, and changing effect
    means scrolling down.
17. Why are hand-written wasm, Perl and SQL greyed? Finish them. Then the
    finale in x86.
18. When I share the link there is no preview image: make sure there is
    always a preview, on every page.
19. *(after a Reddit comment)* "hand-written" needs clarifying. *(after
    another)* Can we be as transparent as for the other projects?

## Part 2 · The port agents' briefs

Every brief carried the same core, then one paragraph per language.

**Core (all ports).**
- Read `spec/ABI.md` (the contract and the determinism traps), the Go
  effects in `go/internal/fx/`, their helpers, and an existing port for
  orientation; write the language *the way an expert in it would*,
  idiomatic and commented, as teaching material, not a transliteration.
- Same optimisation ideas as the reference (tables, hoisted invariants), no
  explicit SIMD, no allocation per frame.
- Mark each effect's hot loop between `@excerpt SCENE` and `@end`; write a
  short `NOTES.md` with one or two sentences per effect on what the
  language does differently, and a "Pixel differences" section.
- Verify with `tools/check.mjs`: 0 differing pixels outside the finale at
  several sizes and frames; for the finale, prove the name is the only
  cause. Where the maths library makes a difference, prove it and document
  it rather than copying the reference's implementation.
- Touch only the port's own directory; do not commit.

**Per language.**
- **C**: C17 to wasm with clang and wasi-libc, `-ffp-contract=off`; mind
  initialiser evaluation order, float literals and float-to-int.
- **Rust**: no dependencies, edition 2024, `unsafe` only at the boundary;
  justify the global-state idiom; iterators where they remove bounds
  checks.
- **JavaScript**: no wasm; `Math.fround` after every float32 operation;
  typed arrays; monomorphic, allocation-free hot loops.
- **Zig**: freestanding wasm; comptime tables where natural; explicit
  allocators; check Debug/ReleaseSafe builds trip no safety check.
- **C++**: C++23, libc++, no exceptions, no RTTI.
- **AssemblyScript**: explicit `f32`/`f64` types, `unchecked()` where it
  removes bounds checks; compare with the JavaScript port.
- **Python**: Pyodide; the default rung vectorised with NumPy in float32, the
  naive rungs honest plain-Python loops.
- **Perl**: find a Perl compiled to wasm that runs in a worker and in Node,
  fetched and checked against a pinned hash; float32 with `pack 'f'`.
- **SQL**: sql.js; the pixels computed by SQL, no JavaScript maths; measure
  and explain any float32 difference rather than hide it.
- **Raw WebAssembly (WAT)**: no compiler; build or ship the sine table, and
  report how many entries match the reference bit for bit.
- **x86 assembly**: NASM, SSE scalar only (never x87), a small interpreter
  in C compiled to wasm that decodes only the instructions the program
  uses.
- **Ladders** (a later brief to each port): implement the naive rungs of the
  plasma, tunnel and Mandelbrot as an honest first attempt in that
  language, "not a strawman", with the same arithmetic as the reference.
