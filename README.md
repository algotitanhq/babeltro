# babeltro

A demoscene intro computed pixel by pixel on the CPU, then rewritten in
several languages. Babel for the languages, "-tro" for the intro: every
language remakes the same production.

The point is not to find out which language wins. It is to see what each
language makes you write differently to produce **the same image**: memory
model, parallelism, floating-point arithmetic, bounds checks, bindings to the
system.

## Rules

Every port must render, at the same instant, the same image as the Go
reference, byte for byte. The only intended difference is the language's own
words — its name in the logo, the scroller and the HUD, and what it calls its
workers (`go/internal/brand`). Any other difference is measured and
explained, never ignored.

## Ports

| Directory | Language | Status |
| --- | --- | --- |
| `go/` | Go | reference: nine scenes, window, HUD, `-bench`, `-dump` |
| `goose/` | Goose | test bench: the PLASMA scene only (see `goose/RESULTS.md`) |
