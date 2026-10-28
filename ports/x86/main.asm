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
;   0x008000   256 B           scene state (the variables below)
;   0x010000   8193 x 4 B      SIN table, f32: sin(2*pi*i/8192), i = 0..8192
;   0x020000   256 x 4 B       SUNSET palette (plasma)
;   0x020400   256 x 4 B       EMBER palette  (fire)
;   0x100000   w x h x 4 B     FRAMEBUFFER, the address bb_init returns
;   after it                   plasma: rad (w*h f32), sx, sy, sxy
;                              fire:   heat (w*h bytes), after the plasma's
;   0x2000000                  top of the stack, growing down
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
W1:     resd 1          ; w-1, the fire's right edge
FB:     resd 1          ; framebuffer address
RAD:    resd 1          ; plasma: distance to the centre, per pixel
SX:     resd 1          ; plasma: per-column sines
SY:     resd 1          ; plasma: per-row sines
SXY:    resd 1          ; plasma: per-diagonal sines
HEAT:   resd 1          ; fire: one byte per pixel
SCENE:  resd 1          ; current scene number
STEP:   resd 1          ; rung of its ladder, 0 = optimised
READY:  resd 1          ; tables built?
RNG:    resd 1          ; fire: xorshift32 state
PHASE:  resd 1          ; plasma: f32, t*2.6
TIME:   resd 1          ; f32, the frame's t
SCRAT:  resd 8          ; spill slots

absolute 0x10000
sintab: resd 8193

absolute 0x20000
sunset: resd 256
ember:  resd 256

HEAP    equ 0x100000

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
        mov     dword [READY], 1
.layout:
        mov     eax, [W]
        imul    eax, [H]
        mov     [N], eax
        mov     ebx, HEAP
        mov     [FB], ebx
        lea     ebx, [ebx+eax*4]        ; rad: w*h floats
        mov     [RAD], ebx
        lea     ebx, [ebx+eax*4]        ; sx: w floats
        mov     [SX], ebx
        mov     ecx, [W]
        lea     ebx, [ebx+ecx*4]        ; sy: h floats
        mov     [SY], ebx
        mov     ecx, [H]
        lea     ebx, [ebx+ecx*4]        ; sxy: w+h floats
        mov     [SXY], ebx
        mov     ecx, [W]
        add     ecx, [H]
        lea     ebx, [ebx+ecx*4]        ; heat: w*h bytes
        mov     [HEAT], ebx
        mov     eax, [FB]
        ret

; start(eax = scene): begin a scene from a fresh state. A scene this port
; does not have draws nothing.
start:
        mov     [SCENE], eax
        mov     dword [STEP], 0
        cmp     eax, 2
        je      plasma_start
        cmp     eax, 6
        je      fire_start
        ret

; step(eax = rung)
step:
        mov     [STEP], eax
        ret

; render(eax = n): frame n, at t = n/60 s. The division is f64, as in Go,
; and t is then rounded once to f32 for the scenes that want it.
render:
        cvtsi2sd xmm0, eax
        divsd   xmm0, [f64_60]
        cvtsd2ss xmm0, xmm0
        movss   [TIME], xmm0
        mov     ecx, [SCENE]
        cmp     ecx, 2
        je      plasma_render
        cmp     ecx, 6
        je      fire_render
        ret

%include "fmath.asm"
%include "palette.asm"
%include "plasma.asm"
%include "fire.asm"

; ---------------------------------------------------------------------------
; constants
; ---------------------------------------------------------------------------

align 8
f64_60:     dq 60.0
zero:       dd 0
c255:       dd 255
three:      dd 3
