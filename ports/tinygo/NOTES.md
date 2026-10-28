# TinyGo: the same Go, another compiler

This is not a port. It is the Go version — the very same files under
`go/` — built by TinyGo instead of the official Go compiler. TinyGo
compiles through LLVM, like clang and rustc; the official compiler has its
own WebAssembly backend, which keeps goroutines working by making every
function resumable, with its stack in linear memory. That machinery is
what the extra milliseconds pay for, and why the module is 2 MB against
TinyGo's 94 KB. Same source, same pixels, different speed: the timings in
this lab measure compilers as much as languages.

## How TinyGo differs, scene by scene

- **ROTOZOOM**: the one scene where TinyGo is slower than Go's own
  backend (0.95 against 0.69 ms at 640×360): the texture lookup's masked
  index keeps a bounds check LLVM does not remove here.
- **METABALLS**: 3.3x faster than Go's own wasm backend, the largest gap:
  the inner loop over the six balls stays in registers instead of the
  linear-memory stack.

## Pixel differences

None, in any scene, finale included: it is the same program, so it spells
`GO` too.
