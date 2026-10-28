; grid: the synthwave staple, an infinite checker floor rushing at the
; camera under a banded sun. The floor is a per-pixel perspective divide,
; the lines come from the fractional part of the world coordinates. Go mixes
; f32 and f64 here (its clamp works in f64): ss and sd follow it, op by op.

G_HOR    equ SCRAT+0            ; f32 frame constants
G_ASP    equ SCRAT+4
G_CX     equ SCRAT+8
G_T      equ SCRAT+12
G_SUNY   equ SCRAT+16
G_SUNR   equ SCRAT+20
G_NSUNR  equ SCRAT+24
G_SKYR   equ SCRAT+28           ; f32 row constants
G_SKYG   equ SCRAT+32
G_SKYB   equ SCRAT+36
G_FLOOR  equ SCRAT+40           ; int: is this row floor?
G_FR     equ SCRAT+44
G_FG     equ SCRAT+48
G_FB     equ SCRAT+52
G_KX     equ SCRAT+56
G_DZ     equ SCRAT+60
G_LZ     equ SCRAT+64
G_FADE   equ SCRAT+68
G_SUNROW equ SCRAT+72           ; int
G_STRIPE equ SCRAT+76           ; int
G_SG     equ SCRAT+80
G_SB     equ SCRAT+84
G_DYC    equ SCRAT+88
G_Z      equ SCRAT+92
G_PERIOD equ SCRAT+96
G_LWZ    equ SCRAT+100
G_AMP    equ SCRAT+104
G_FY     equ SCRAT+108
G_SKY    equ SCRAT+120          ; f64

; CLAMPF xmm: clamp an f32 to [0,1], as Go's Clamp01 does in f64 (the
; same result for an f32 input). Compares, not maxss: -0 stays -0.
%macro CLAMPF 1
        comiss  %1, [f32_zero]
        jae     %%pos
        movss   %1, [f32_zero]
%%pos:  comiss  %1, [f32_one]
        jbe     %%ok
        movss   %1, [f32_one]
%%ok:
%endmacro

; frac (xmm0) -> xmm0 in [0,1), negatives included (clobbers eax, xmm2)
frac:
        cvttss2si eax, xmm0
        cvtsi2ss xmm2, eax
        subss   xmm0, xmm2
        comiss  xmm0, [f32_zero]
        jae     .ok
        addss   xmm0, [f32_one]
.ok:    ret

; line_glow (xmm0 = f, xmm1 = width) -> xmm0: 1 on a grid line, falling to
; 0 over the width (clobbers xmm2)
line_glow:
        comiss  xmm0, [f32_half]
        jbe     .near
        movss   xmm2, [f32_one]
        subss   xmm2, xmm0
        movss   xmm0, xmm2
.near:  comiss  xmm0, xmm1
        jae     .off
        divss   xmm0, xmm1
        movss   xmm2, [f32_one]
        subss   xmm2, xmm0
        movss   xmm0, xmm2
        ret
.off:   xorps   xmm0, xmm0
        ret

; MIX dst, target: dst += (target - dst)*xmm3, the sun's edge
%macro MIX 2
        movss   xmm0, %2
        subss   xmm0, %1
        mulss   xmm0, xmm3
        addss   %1, xmm0
%endmacro

; BYTE xmm, k: an f32 channel to byte k of the pixel at [edi]
%macro BYTE 2
        cvtss2sd xmm3, %1
        call    to_byte
        mov     [edi+%2], cl
%endmacro

grid_render:
        cvtsi2ss xmm7, [H]
        movss   xmm0, xmm7
        mulss   xmm0, [f32_0_52]
        movss   [G_HOR], xmm0           ; horizon = h*0.52
        movss   xmm1, xmm7
        mulss   xmm1, [f32_0_13]
        subss   xmm0, xmm1
        movss   [G_SUNY], xmm0          ; sun_y = horizon - h*0.13
        movss   xmm1, xmm7
        mulss   xmm1, [f32_0_16]
        movss   [G_SUNR], xmm1          ; sun_r = h*0.16
        xorps   xmm1, [sign32]
        movss   [G_NSUNR], xmm1
        cvtsi2ss xmm0, [W]
        movss   xmm1, xmm7
        divss   xmm1, xmm0
        movss   [G_ASP], xmm1           ; asp = h/w
        mulss   xmm0, [f32_half]
        movss   [G_CX], xmm0            ; cx = sun_x = w*0.5
        movss   xmm0, [TIME]
        movss   [G_T], xmm0
        mov     edi, [FB]
        xor     esi, esi
.row:   cvtsi2ss xmm7, esi
        movss   [G_FY], xmm7
        movss   xmm0, xmm7              ; the sky: sky = clamp01(fy/horizon),
        divss   xmm0, [G_HOR]           ; in f64
        cvtss2sd xmm0, xmm0
        maxsd   xmm0, [f64_zero]
        minsd   xmm0, [f64_one]
        movsd   [G_SKY], xmm0
        mulsd   xmm0, [f64_0_18]
        mulsd   xmm0, [G_SKY]
        addsd   xmm0, [f64_0_03]
        cvtsd2ss xmm0, xmm0
        movss   [G_SKYR], xmm0          ; 0.03 + 0.18*sky*sky
        movsd   xmm0, [G_SKY]
        mulsd   xmm0, [f64_0_05]
        addsd   xmm0, [f64_0_01]
        cvtsd2ss xmm0, xmm0
        movss   [G_SKYG], xmm0          ; 0.01 + 0.05*sky
        movsd   xmm0, [G_SKY]
        mulsd   xmm0, [f64_0_22]
        addsd   xmm0, [f64_0_08]
        cvtsd2ss xmm0, xmm0
        movss   [G_SKYB], xmm0          ; 0.08 + 0.22*sky

        mov     dword [G_FLOOR], 0
        comiss  xmm7, [G_HOR]
        jbe     .sun
        mov     dword [G_FLOOR], 1      ; the floor row: everything that
        movss   xmm0, xmm7              ; depends only on the row
        subss   xmm0, [G_HOR]
        movss   [G_DZ], xmm0            ; dz = fy - horizon
        cvtsi2ss xmm1, [H]
        mulss   xmm1, [f32_0_55]
        divss   xmm1, xmm0
        movss   [G_Z], xmm1             ; z = h*0.55/dz
        movss   xmm6, xmm1              ; wz = z*2.5 + t*5.5
        mulss   xmm6, [f32_2_5]
        movss   xmm0, [G_T]
        mulss   xmm0, [f32_5_5]
        addss   xmm6, xmm0
        cvtsi2ss xmm0, [W]              ; kx = z/(w*0.5)*asp*2
        mulss   xmm0, [f32_half]
        divss   xmm1, xmm0
        mulss   xmm1, [G_ASP]
        mulss   xmm1, [f32_2]
        movss   [G_KX], xmm1
        movss   xmm0, [f32_one]         ; fade_x = clamp((1/kx - 1.5)/2)
        divss   xmm0, xmm1
        subss   xmm0, [f32_1_5]
        divss   xmm0, [f32_2]
        CLAMPF  xmm0
        movss   [G_FADE], xmm0
        movss   xmm0, [G_DZ]            ; period = dz*dz/(1.375*h)
        mulss   xmm0, xmm0
        cvtsi2ss xmm1, [H]
        mulss   xmm1, [f32_1_375]
        divss   xmm0, xmm1
        movss   [G_PERIOD], xmm0
        movss   xmm1, [f32_0_024]       ; lw_z = 0.014 + 0.024/z
        divss   xmm1, [G_Z]
        addss   xmm1, [f32_0_014]
        movss   [G_LWZ], xmm1
        mov     dword [G_AMP], 0x3F800000 ; amp_z = 1.0
        movss   xmm2, [f32_half]        ; min_w = 0.5/period: widen a line
        divss   xmm2, xmm0              ; narrower than a pixel, and dim it
        comiss  xmm1, xmm2
        jae     .wide
        divss   xmm1, xmm2
        movss   [G_AMP], xmm1           ; amp_z = lw_z/min_w
        movss   [G_LWZ], xmm2           ; lw_z = min_w
.wide:  movss   xmm0, xmm6
        call    frac
        movss   xmm1, [G_LWZ]
        call    line_glow
        mulss   xmm0, [G_AMP]           ; line_z
        movss   xmm1, [G_PERIOD]        ; *= clamp((period - 1.5)/2)
        subss   xmm1, [f32_1_5]
        divss   xmm1, [f32_2]
        CLAMPF  xmm1
        mulss   xmm0, xmm1
        movss   xmm1, [G_Z]             ; *= clamp(1/(1 + z*z*0.004)): fog
        mulss   xmm1, xmm1
        mulss   xmm1, [f32_0_004]
        addss   xmm1, [f32_one]
        movss   xmm2, [f32_one]
        divss   xmm2, xmm1
        CLAMPF  xmm2
        mulss   xmm0, xmm2
        movss   [G_LZ], xmm0
        movss   xmm3, [f32_0_02]        ; the floor colour
        movss   xmm4, [f32_0_01]
        movss   xmm5, [f32_0_06]
        movss   xmm0, [G_DZ]            ; the haze near the horizon, in f64:
        cvtsi2ss xmm1, [H]              ; clamp01(dz/(h*0.12))
        mulss   xmm1, [f32_0_12]
        divss   xmm0, xmm1
        cvtss2sd xmm0, xmm0
        maxsd   xmm0, [f64_zero]
        minsd   xmm0, [f64_one]
        comisd  xmm0, [f64_one]
        jae     .lines
        movsd   xmm1, [f64_one]
        subsd   xmm1, xmm0              ; 1 - haze
        movsd   xmm0, xmm1
        mulsd   xmm0, [f64_0_25]
        cvtsd2ss xmm0, xmm0
        addss   xmm3, xmm0
        movsd   xmm0, xmm1
        mulsd   xmm0, [f64_0_05]
        cvtsd2ss xmm0, xmm0
        addss   xmm4, xmm0
        mulsd   xmm1, [f64_0_35]
        cvtsd2ss xmm1, xmm1
        addss   xmm5, xmm1
.lines: movss   xmm0, [G_LZ]            ; plus the cross line
        mulss   xmm0, [f32_0_55]
        addss   xmm3, xmm0
        movss   [G_FR], xmm3
        movss   xmm0, [G_LZ]
        mulss   xmm0, [f32_0_35]
        addss   xmm4, xmm0
        movss   [G_FG], xmm4
        movss   xmm0, [G_LZ]
        mulss   xmm0, [f32_0_75]
        addss   xmm5, xmm0
        movss   [G_FB], xmm5

.sun:   mov     dword [G_SUNROW], 0     ; the sun: bounding rows first
        mov     dword [G_STRIPE], 0
        movss   xmm0, xmm7
        subss   xmm0, [G_SUNY]
        movss   [G_DYC], xmm0           ; dyc = fy - sun_y
        comiss  xmm0, [G_NSUNR]
        jbe     .pixels
        comiss  xmm0, [G_SUNR]
        jae     .pixels
        movss   xmm1, [G_HOR]
        addss   xmm1, [f32_2]
        comiss  xmm7, xmm1
        jae     .pixels
        mov     dword [G_SUNROW], 1
        movss   xmm1, [G_SUNR]          ; the bands: fy > sun_y - sun_r*0.45
        mulss   xmm1, [f32_0_45]        ; and int(fy) % 9 < 4
        movss   xmm2, [G_SUNY]
        subss   xmm2, xmm1
        comiss  xmm7, xmm2
        jbe     .shade
        mov     eax, esi
        xor     edx, edx
        div     dword [nine]
        cmp     edx, 4
        jge     .shade
        mov     dword [G_STRIPE], 1
.shade: movss   xmm0, [G_SUNY]          ; u = clamp01((fy - (sun_y - sun_r))
        subss   xmm0, [G_SUNR]          ;              / (2*sun_r)), f64
        movss   xmm1, xmm7
        subss   xmm1, xmm0
        movss   xmm0, [G_SUNR]
        addss   xmm0, xmm0
        divss   xmm1, xmm0
        cvtss2sd xmm1, xmm1
        maxsd   xmm1, [f64_zero]
        minsd   xmm1, [f64_one]
        movsd   xmm0, xmm1
        mulsd   xmm0, [f64_0_7]
        movsd   xmm2, [f64_0_95]
        subsd   xmm2, xmm0
        cvtsd2ss xmm2, xmm2
        movss   [G_SG], xmm2            ; 0.95 - 0.7*u
        mulsd   xmm1, [f64_0_55]
        addsd   xmm1, [f64_0_25]
        cvtsd2ss xmm1, xmm1
        movss   [G_SB], xmm1            ; 0.25 + 0.55*u

.pixels:
        xor     ecx, ecx
; @excerpt GRID
.px:    movss   xmm5, [G_SKYR]          ; r, g, b = the sky
        movss   xmm6, [G_SKYG]
        movss   xmm7, [G_SKYB]
        cmp     dword [G_SUNROW], 0
        je      .floor
        cmp     dword [G_STRIPE], 0
        jne     .floor
        cvtsi2ss xmm1, ecx
        subss   xmm1, [G_CX]            ; dx from the sun's centre
        comiss  xmm1, [G_NSUNR]
        jbe     .floor
        comiss  xmm1, [G_SUNR]
        jae     .floor
        mulss   xmm1, xmm1              ; d = sqrt(dx*dx + dyc*dyc)
        movss   xmm2, [G_DYC]
        mulss   xmm2, xmm2
        addss   xmm1, xmm2
        sqrtss  xmm1, xmm1
        comiss  xmm1, [G_SUNR]
        jae     .floor
        movss   xmm3, [G_SUNR]          ; edge = clamp((sun_r - d)/(sun_r*0.025))
        subss   xmm3, xmm1
        movss   xmm2, [G_SUNR]
        mulss   xmm2, [f32_0_025]
        divss   xmm3, xmm2
        CLAMPF  xmm3
        MIX     xmm5, [f32_one]         ; mix towards the sun's colour
        MIX     xmm6, [G_SG]
        MIX     xmm7, [G_SB]
.floor: cmp     dword [G_FLOOR], 0
        je      .pack
        cvtsi2ss xmm4, ecx              ; how far this ray slides sideways
        subss   xmm4, [G_CX]            ; between rows: the line must be at
        movss   xmm1, xmm4              ; least that wide, and dimmed by it
        andps   xmm1, [abs32]           ; off = |x - cx|
        divss   xmm1, [G_DZ]            ; slide = off/dz
        movss   xmm3, [f32_0_044]
        divss   xmm3, [G_KX]            ; w_px = 2*lw_x/kx
        comiss  xmm1, xmm3
        jbe     .wpx
        movss   xmm3, xmm1
.wpx:   comiss  xmm3, [f32_one]
        jae     .wok
        movss   xmm3, [f32_one]
.wok:   movss   xmm0, xmm4              ; line_x = glow(frac((x-cx)*kx + 0.37),
        mulss   xmm0, [G_KX]            ;   w_px*kx*0.5) * (2*lw_x/kx/w_px) * fade_x
        addss   xmm0, [f32_0_37]
        call    frac
        movss   xmm1, xmm3
        mulss   xmm1, [G_KX]
        mulss   xmm1, [f32_half]
        call    line_glow
        movss   xmm1, [f32_0_044]
        divss   xmm1, [G_KX]
        divss   xmm1, xmm3
        mulss   xmm0, xmm1
        mulss   xmm0, [G_FADE]
        movss   xmm4, [G_LZ]            ; line = max(line_x, line_z)
        comiss  xmm0, xmm4
        ja      .lx
        movss   xmm0, xmm4
.lx:    movss   xmm5, [G_FR]            ; floor - k*line_z + k*line
        movss   xmm1, xmm4
        mulss   xmm1, [f32_0_55]
        subss   xmm5, xmm1
        movss   xmm1, xmm0
        mulss   xmm1, [f32_0_55]
        addss   xmm5, xmm1
        movss   xmm6, [G_FG]
        movss   xmm1, xmm4
        mulss   xmm1, [f32_0_35]
        subss   xmm6, xmm1
        movss   xmm1, xmm0
        mulss   xmm1, [f32_0_35]
        addss   xmm6, xmm1
        movss   xmm7, [G_FB]
        movss   xmm1, xmm4
        mulss   xmm1, [f32_0_75]
        subss   xmm7, xmm1
        movss   xmm1, xmm0
        mulss   xmm1, [f32_0_75]
        addss   xmm7, xmm1
.pack:  push    ecx
        BYTE    xmm5, 0
        BYTE    xmm6, 1
        BYTE    xmm7, 2
        pop     ecx
        mov     byte [edi+3], 0xFF
        add     edi, 4
        inc     ecx
        cmp     ecx, [W]
        jl      .px
; @end
        inc     esi
        cmp     esi, [H]
        jl      .row
        ret

align 16
abs32:     dd 0x7FFFFFFF, 0, 0, 0
f32_zero:  dd 0.0
f32_2:     dd 2.0
f32_0_52:  dd 0.52
f32_0_13:  dd 0.13
f32_2_5:   dd 2.5
f32_5_5:   dd 5.5
f32_1_5:   dd 1.5
f32_1_375: dd 1.375
f32_0_024: dd 0.024
f32_0_014: dd 0.014
f32_0_004: dd 0.004
f32_0_01:  dd 0.01
f32_0_06:  dd 0.06
f32_0_12:  dd 0.12
f32_0_75:  dd 0.75
f32_0_044: dd 0.044                 ; 2*lw_x, lw_x = 0.022: exact doubling
f32_0_37:  dd 0.37
nine:      dd 9
align 8
f64_0_18:  dq 0.18
f64_0_03:  dq 0.03
f64_0_05:  dq 0.05
f64_0_01:  dq 0.01
f64_0_22:  dq 0.22
f64_0_08:  dq 0.08
f64_0_95:  dq 0.95
