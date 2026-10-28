; rotozoom: the purest demoscene move. Build a texture once, then every
; frame rotate and zoom the sampling grid over it. Per pixel: a few
; multiplies and one lookup.

; COS xmm: fmath.Cos from the table, in place (clobbers eax)
%macro COS 1
        mulss   %1, [inv2pi]
        cvttss2si eax, %1
        and     eax, 8191
        movss   %1, [costab+eax*4]
%endmacro

R_FX    equ SCRAT+0             ; f64 texture coordinates, in tiles
R_FY    equ SCRAT+8
R_V     equ SCRAT+16            ; f64 the plasma value
R_P     equ SCRAT+24            ; f64 hsl: the two levels
R_Q     equ SCRAT+32
R_H     equ SCRAT+40            ; f64 hue
R_CX    equ SCRAT+48            ; f32 render constants
R_CY    equ SCRAT+52
R_ZOOM  equ SCRAT+56
R_OFFX  equ SCRAT+60
R_OFFY  equ SCRAT+64
R_DYS   equ SCRAT+68
R_DYC   equ SCRAT+72
R_DARK  equ SCRAT+76            ; on a grid line?

rotozoom_start:
        cmp     dword [TEXOK], 0
        jne     .done
        call    build_texture           ; once, then kept: 1 MiB
        mov     dword [TEXOK], 1
.done:  ret

; a sine of the texture, xmm0 = (%1 * 2pi * %2) for a tile coordinate
%macro TURNS 2
        movsd   xmm0, [%1]
        mulsd   xmm0, [two_pi]
        mulsd   xmm0, [%2]
%endmacro

; build_texture: a tileable rainbow plasma, about a million f64 sines.
; Every frequency is a whole number of cycles per 512-pixel tile.
build_texture:
        mov     edi, texture
        xor     esi, esi                ; y
.row:   cvtsi2ss xmm0, esi              ; Go rounds the coordinates to f32
        divss   xmm0, [f32_512]
        cvtss2sd xmm0, xmm0
        movsd   [R_FY], xmm0
        xor     ebx, ebx                ; x
.px:    cvtsi2ss xmm0, ebx
        divss   xmm0, [f32_512]
        cvtss2sd xmm0, xmm0
        movsd   [R_FX], xmm0
        TURNS   R_FX, f64_3             ; sin(fx*2pi*3 + fy*2pi*2)*0.5
        movsd   xmm3, xmm0
        TURNS   R_FY, f64_2
        addsd   xmm0, xmm3
        call    sin64
        mulsd   xmm0, [f64_half]
        movsd   [R_V], xmm0
        TURNS   R_FX, f64_4             ;  + sin(fy*2pi*5 - fx*2pi*4)*0.3
        movsd   xmm3, xmm0
        TURNS   R_FY, f64_5
        subsd   xmm0, xmm3
        call    sin64
        mulsd   xmm0, [f64_0_3]
        addsd   xmm0, [R_V]
        movsd   [R_V], xmm0
        movsd   xmm0, [R_FX]            ;  + sin((fx+fy)*2pi*7)*0.2
        addsd   xmm0, [R_FY]
        mulsd   xmm0, [two_pi]
        mulsd   xmm0, [f64_7]
        call    sin64
        mulsd   xmm0, [f64_0_2]
        addsd   xmm0, [R_V]
        movsd   [R_V], xmm0
        lea     eax, [ebx-256]          ; concentric rings, also periodic:
        cvtsi2sd xmm0, eax              ; rr = sqrt(dx*dx + dy*dy)/512*12
        mulsd   xmm0, xmm0
        lea     eax, [esi-256]
        cvtsi2sd xmm1, eax
        mulsd   xmm1, xmm1
        addsd   xmm0, xmm1
        sqrtsd  xmm0, xmm0
        divsd   xmm0, [f64_512]
        mulsd   xmm0, [f64_12]
        mulsd   xmm0, [two_pi]
        call    sin64                   ; v += sin(rr*2pi)*0.35
        mulsd   xmm0, [f64_0_35]
        addsd   xmm0, [R_V]
        movsd   [R_V], xmm0
        mulsd   xmm0, [f64_0_55]        ; hue = mod(v*0.55 + 0.5, 1): for a
        addsd   xmm0, [f64_half]        ; small x that is x - trunc(x), exact
        cvttsd2si eax, xmm0
        cvtsi2sd xmm1, eax
        subsd   xmm0, xmm1
        xorpd   xmm1, xmm1
        comisd  xmm0, xmm1
        jae     .hue
        addsd   xmm0, [f64_one]
.hue:   movsd   [R_H], xmm0
        movsd   xmm0, [R_V]             ; hsl, s = 0.70, l = 0.48 + 0.14*v
        mulsd   xmm0, [f64_0_14]
        addsd   xmm0, [f64_0_48]
        comisd  xmm0, [f64_half]
        jae     .light
        movsd   xmm2, [f64_one]         ; q = l*(1 + s)
        addsd   xmm2, [f64_0_7]
        movsd   xmm1, xmm0
        mulsd   xmm1, xmm2
        jmp     .q
.light: movsd   xmm1, xmm0              ; q = l + s - l*s
        addsd   xmm1, [f64_0_7]
        movsd   xmm2, xmm0
        mulsd   xmm2, [f64_0_7]
        subsd   xmm1, xmm2
.q:     movsd   [R_Q], xmm1
        addsd   xmm0, xmm0              ; p = 2*l - q
        subsd   xmm0, xmm1
        movsd   [R_P], xmm0
        mov     edx, 0                  ; dark grid lines every 64 pixels:
        mov     eax, ebx                ; x % 64 < 3 or y % 64 < 3
        and     eax, 63
        cmp     eax, 3
        jl      .dark
        mov     eax, esi
        and     eax, 63
        cmp     eax, 3
        jge     .lit
.dark:  mov     edx, 1
.lit:   mov     [R_DARK], edx
        movsd   xmm0, [R_H]
        addsd   xmm0, [third]
        call    hue_to_rgb
        call    channel_byte
        mov     [edi], cl               ; red
        movsd   xmm0, [R_H]
        call    hue_to_rgb
        call    channel_byte
        mov     [edi+1], cl             ; green
        movsd   xmm0, [R_H]
        subsd   xmm0, [third]
        call    hue_to_rgb
        call    channel_byte
        mov     [edi+2], cl             ; blue
        mov     byte [edi+3], 0xFF
        add     edi, 4
        inc     ebx
        cmp     ebx, 512
        jl      .px
        inc     esi
        cmp     esi, 512
        jl      .row
        ret

; channel_byte (xmm0) -> ecx: darkened on a grid line, then to a byte
channel_byte:
        movsd   xmm3, xmm0
        cmp     dword [R_DARK], 0
        je      .byte
        mulsd   xmm3, [f64_0_28]
.byte:  jmp     to_byte

; hue_to_rgb (xmm0 = t, [R_P], [R_Q]) -> xmm0: one channel of hsl
hue_to_rgb:
        xorpd   xmm1, xmm1
        comisd  xmm0, xmm1
        jae     .a
        addsd   xmm0, [f64_one]
.a:     comisd  xmm0, [f64_one]
        jbe     .b
        subsd   xmm0, [f64_one]
.b:     comisd  xmm0, [sixth]           ; rising: p + (q-p)*6*t
        jae     .c
        movsd   xmm1, [R_Q]
        subsd   xmm1, [R_P]
        mulsd   xmm1, [f64_6]
        mulsd   xmm1, xmm0
        addsd   xmm1, [R_P]
        movsd   xmm0, xmm1
        ret
.c:     comisd  xmm0, [f64_half]        ; flat top: q
        jae     .d
        movsd   xmm0, [R_Q]
        ret
.d:     comisd  xmm0, [two_thirds]      ; falling: p + (q-p)*(2/3 - t)*6
        jae     .e
        movsd   xmm1, [two_thirds]
        subsd   xmm1, xmm0
        movsd   xmm0, [R_Q]
        subsd   xmm0, [R_P]
        mulsd   xmm0, xmm1
        mulsd   xmm0, [f64_6]
        addsd   xmm0, [R_P]
        ret
.e:     movsd   xmm0, [R_P]             ; flat bottom: p
        ret

rotozoom_render:
        movss   xmm7, [TIME]
        movss   xmm0, xmm7              ; the angle, t*0.45
        mulss   xmm0, [f32_0_45]
        movss   xmm5, xmm0
        COS     xmm5                    ; xmm5 = cos a
        SIN     xmm0
        movss   xmm6, xmm0              ; xmm6 = sin a
        movss   xmm0, xmm7              ; zoom: (0.55 + 0.45*sin(t*0.7) + 0.35)
        mulss   xmm0, [f32_0_7]         ;       / w * 6.5, the breathing
        SIN     xmm0                    ;       folded with the pixel scale
        mulss   xmm0, [f32_0_45]
        addss   xmm0, [f32_0_55]
        addss   xmm0, [f32_0_35]
        cvtsi2ss xmm1, [W]
        divss   xmm0, xmm1
        mulss   xmm0, [f32_6_5]
        movss   [R_ZOOM], xmm0
        movss   xmm0, xmm7              ; offx = sin(t*0.31)*180 + t*26
        mulss   xmm0, [f32_0_31]
        SIN     xmm0
        mulss   xmm0, [f32_180]
        movss   xmm1, xmm7
        mulss   xmm1, [f32_26]
        addss   xmm0, xmm1
        movss   [R_OFFX], xmm0
        movss   xmm0, xmm7              ; offy = cos(t*0.27)*180 + t*19
        mulss   xmm0, [f32_0_27]
        COS     xmm0
        mulss   xmm0, [f32_180]
        movss   xmm1, xmm7
        mulss   xmm1, [f32_19]
        addss   xmm0, xmm1
        movss   [R_OFFY], xmm0
        cvtsi2ss xmm0, [W]
        mulss   xmm0, [f32_half]
        movss   [R_CX], xmm0
        cvtsi2ss xmm0, [H]
        mulss   xmm0, [f32_half]
        movss   [R_CY], xmm0
        movss   xmm4, [R_ZOOM]
        mov     edi, [FB]
        xor     esi, esi
; @excerpt ROTOZOOM
.row:   cvtsi2ss xmm0, esi
        subss   xmm0, [R_CY]            ; dy, and its two products, per row
        movss   xmm1, xmm0
        mulss   xmm0, xmm6
        movss   [R_DYS], xmm0           ; dy*sin a
        mulss   xmm1, xmm5
        movss   [R_DYC], xmm1           ; dy*cos a
        xor     ecx, ecx
.px:    cvtsi2ss xmm0, ecx
        subss   xmm0, [R_CX]            ; dx
        movss   xmm1, xmm0
        mulss   xmm0, xmm5              ; rotate, scale, wrap into the tile:
        subss   xmm0, [R_DYS]           ; tx = (dx*cos - dy*sin)*zoom*34
        mulss   xmm0, xmm4
        mulss   xmm0, [f32_34]
        addss   xmm0, [R_OFFX]
        cvttss2si eax, xmm0
        and     eax, 511                ; ix
        mulss   xmm1, xmm6              ; ty = (dx*sin + dy*cos)*zoom*34
        addss   xmm1, [R_DYC]
        mulss   xmm1, xmm4
        mulss   xmm1, [f32_34]
        addss   xmm1, [R_OFFY]
        cvttss2si edx, xmm1
        and     edx, 511                ; iy
        shl     edx, 9
        add     eax, edx
        mov     eax, [texture+eax*4]    ; tex[iy*512 + ix]
        mov     [edi+ecx*4], eax
        inc     ecx
        cmp     ecx, [W]
        jl      .px
        lea     edi, [edi+ecx*4]
        inc     esi
        cmp     esi, [H]
        jl      .row
; @end
        ret

align 8
f64_2:      dq 2.0
f64_3:      dq 3.0
f64_5:      dq 5.0
f64_6:      dq 6.0
f64_7:      dq 7.0
f64_0_2:    dq 0.2
f64_0_3:    dq 0.3
f64_0_35:   dq 0.35
f64_512:    dq 512.0
f64_0_55:   dq 0.55
f64_0_14:   dq 0.14
f64_0_48:   dq 0.48
f64_0_7:    dq 0.70
f64_0_28:   dq 0.28
third:      dq 0x3FD5555555555555   ; 1.0/3, correctly rounded
sixth:      dq 0x3FC5555555555555   ; 1.0/6
two_thirds: dq 0x3FE5555555555555   ; 2.0/3
f32_512:    dd 512.0
f32_0_35:   dd 0.35
f32_6_5:    dd 6.5
f32_0_31:   dd 0.31
f32_0_27:   dd 0.27
f32_180:    dd 180.0
f32_19:     dd 19.0
f32_34:     dd 34.0
