; babeltro, x86 assembly: the memory map and the entry points
;
; 32-bit protected mode, flat: one address space, no segments to juggle,
; no operating system. NASM assembles this file (and the ones it %includes)
; into a raw binary image, `nasm -f bin`, loaded at address 0 of a 32 MiB
; machine. The browser has no x86, so ports/x86/cpu.c is one: an
; interpreter for exactly the instructions below, compiled to wasm.
;
; Floating point is SSE scalar (movss, addss, mulss, cvttss2si, and their
; sd twins), never the x87. The x87 computes in 80-bit registers and only
; rounds to float when it stores, so a*b+c on the x87 is not a*b+c in Go.
; Every SSE instruction rounds to its own width, once, as Go does.
;
;   address    size            what
;   0x000000   16 B            header: init, start, step, render (dd)
;   0x000010   a few KiB       code, then constants
;   0x008000   1 KiB           scene state (the variables below)
;   0x010000   8193 x 4 B      SIN table, f32: sin(2*pi*i/8192), i = 0..8192
;   0x019000   8193 x 4 B      COS table, f32
;   0x022000   3 x 256 x 4 B   SUNSET, ICE, EMBER palettes
;   0x023000   21 x 8 B        atan series coefficients, (-1)^k/(2k+1)
;   0x024000   1600 x 12 B     starfield: the stars (x, y, z f32)
;   0x029000   1600 x 20 B     starfield: their streaks (x0 y0 x1 y1 colour)
;   0x031000   6 x 12 B        metaballs: per-ball x, y, r^2
;   0x100000   512 x 512 x 4 B rotozoom texture, built on first use
;   0x200000   w x h x 4 B     FRAMEBUFFER, the address bb_init returns
;   after it   w x h x 4 B     BUF1: plasma rad, tunnel depth, stars backdrop
;   after it   w x h x 4 B     BUF2: plasma sx/sy/sxy, tunnel angle, fire heat
;   0x2000000                  top of the stack, growing down
;
; Only one scene runs at a time, so BUF1 and BUF2 are unions, in C terms,
; and each scene's start rebuilds what it keeps there.
;
; Calling convention, for the four entry points and every routine: the
; argument in eax (and edx), the result in eax, any register may be
; clobbered. The host sets esp and pushes a return address it recognises.

bits 32
section .text
org 0

header:
        dd init, start, step, render

; ---------------------------------------------------------------------------
; scene state
; ---------------------------------------------------------------------------

absolute 0x8000
W:      resd 1          ; framebuffer width
H:      resd 1          ; height
N:      resd 1          ; w*h
W1:     resd 1          ; w-1
FB:     resd 1          ; framebuffer address
BUF1:   resd 1
BUF2:   resd 1
RAD     equ BUF1        ; plasma: distance to the centre, per pixel
SX:     resd 1          ; plasma: per-column sines (in BUF2)
SY:     resd 1          ; plasma: per-row sines
SXY:    resd 1          ; plasma: per-diagonal sines
HEAT    equ BUF2        ; fire: one byte per pixel
SCENE:  resd 1          ; current scene number
STEP:   resd 1          ; rung of its ladder, 0 = optimised
READY:  resd 1          ; tables built?
RNG:    resd 1          ; xorshift32 state
PHASE:  resd 1          ; plasma: f32, t*2.6
TIME:   resd 1          ; f32, the frame's t
FRAME:  resd 1          ; n
TEXOK:  resd 1          ; rotozoom texture built?
alignb 8
BEAT:   resq 1          ; f64, n/60
SCRAT:  resd 64         ; per-scene variables and spill slots

absolute 0x10000
sintab: resd 8193
absolute 0x19000
costab: resd 8193
absolute 0x22000
sunset: resd 256
ice:    resd 256
ember:  resd 256
absolute 0x23000
atan_c: resq 21
absolute 0x24000
stars:  resd 1600*3
absolute 0x29000
streaks: resd 1600*5
absolute 0x31000
balls:  resd 6*3
absolute 0x100000
texture: resd 512*512

HEAP    equ 0x200000

section .text                   ; back from the maps to the code

; ---------------------------------------------------------------------------
; the entry points
; ---------------------------------------------------------------------------

; init(eax = w, edx = h) -> eax = framebuffer address.
; The tables are built on the first call; then the buffers are laid out one
; after the other from HEAP, a bump allocator with nothing to free.
init:
        mov     [W], eax
        mov     [H], edx
        dec     eax
        mov     [W1], eax
        cmp     dword [READY], 0
        jne     .layout
        call    build_sintab
        call    build_palettes
        call    build_atan
        mov     dword [READY], 1
.layout:
        mov     eax, [W]
        imul    eax, [H]
        mov     [N], eax
        mov     ebx, HEAP
        mov     [FB], ebx
        lea     ebx, [ebx+eax*4]
        mov     [BUF1], ebx
        lea     ebx, [ebx+eax*4]
        mov     [BUF2], ebx
        mov     [SX], ebx               ; sx: w floats
        mov     ecx, [W]
        lea     ebx, [ebx+ecx*4]        ; sy: h floats
        mov     [SY], ebx
        mov     ecx, [H]
        lea     ebx, [ebx+ecx*4]        ; sxy: w+h floats
        mov     [SXY], ebx
        mov     eax, [FB]
        ret

; start(eax = scene): begin a scene from a fresh state. A scene with
; nothing to prepare (metaballs, grid) starts at `nothing`.
start:
        mov     [SCENE], eax
        mov     dword [STEP], 0
        cmp     eax, 8
        jbe     .ok
        mov     eax, 8                  ; past the last scene: the finale
        mov     [SCENE], eax
.ok:    jmp     [starts+eax*4]

; step(eax = rung)
step:
        mov     [STEP], eax
        ret

; render(eax = n): frame n, at t = n/60 s. The division is f64, as in Go,
; and t is then rounded once to f32 for the scenes that want it.
render:
        mov     [FRAME], eax
        cvtsi2sd xmm0, eax
        divsd   xmm0, [f64_60]
        movsd   [BEAT], xmm0
        cvtsd2ss xmm0, xmm0
        movss   [TIME], xmm0
        mov     ecx, [SCENE]
        jmp     [renders+ecx*4]

nothing:
        ret

; one start and one render per scene, by number
starts:  dd starfield_start, tunnel_start, plasma_start, rotozoom_start
         dd nothing, nothing, fire_start, mandel_start, finale_start
renders: dd starfield_render, tunnel_render, plasma_render, rotozoom_render
         dd metaballs_render, grid_render, fire_render, mandel_render, finale_render

%include "fmath.asm"
%include "palette.asm"
%include "plasma.asm"
%include "fire.asm"
%include "tunnel.asm"
%include "mandelbrot.asm"
%include "rotozoom.asm"
%include "metaballs.asm"
%include "grid.asm"
%include "starfield.asm"
%include "finale.asm"
%include "font.asm"

; ---------------------------------------------------------------------------
; constants
; ---------------------------------------------------------------------------

align 8
f64_60:     dq 60.0
zero:       dd 0
c255:       dd 255
three:      dd 3
