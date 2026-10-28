; tunnel: every pixel is mapped to polar coordinates once, at start. After
; that the per-pixel work is a couple of table lookups and a palette read:
; the geometry is free, which is why it can afford to look this good.

T_CX    equ SCRAT+0
T_CY    equ SCRAT+4
T_SCALE equ SCRAT+8
T_SOFT  equ SCRAT+12
T_ADV   equ SCRAT+16
T_SPIN  equ SCRAT+20

; SIN01 xmm: sin(2*pi*t) for t in turns, from the table (clobbers eax)
%macro SIN01 1
        mulss   %1, [f32_8192]
        cvttss2si eax, %1
        and     eax, 8191
        movss   %1, [sintab+eax*4]
%endmacro

; tunnel_consts: the centre, the depth scale and softness (both follow the
; diagonal, so the rings look the same at any size), and this frame's
; advance and spin
tunnel_consts:
        cvtsi2ss xmm0, [W]
        mulss   xmm0, [f32_half]
        movss   [T_CX], xmm0
        cvtsi2ss xmm0, [H]
        mulss   xmm0, [f32_half]
        movss   [T_CY], xmm0
        mov     eax, [W]
        add     eax, [H]
        cvtsi2ss xmm0, eax
        movss   xmm1, xmm0
        mulss   xmm0, [f32_2_2]
        movss   [T_SCALE], xmm0
        mulss   xmm1, [f32_0_02]
        movss   [T_SOFT], xmm1
        movss   xmm0, [TIME]
        movss   xmm1, xmm0
        mulss   xmm0, [f32_3]
        movss   [T_ADV], xmm0
        mulss   xmm1, [f32_0_25]
        movss   [T_SPIN], xmm1
        ret

; POLAR: pixel (ebx, esi) -> xmm4 = scale/(r + soft), xmm5 = its angle in
; turns (clobbers eax, ecx, edx, xmm0-3)
%macro POLAR 0
        cvtsi2ss xmm1, ebx
        subss   xmm1, [T_CX]            ; dx
        cvtsi2ss xmm0, esi
        subss   xmm0, [T_CY]            ; dy
        movss   xmm2, xmm1
        mulss   xmm2, xmm1
        movss   xmm3, xmm0
        mulss   xmm3, xmm0
        addss   xmm2, xmm3
        sqrtss  xmm2, xmm2              ; r, correctly rounded
        addss   xmm2, [T_SOFT]
        movss   xmm4, [T_SCALE]
        divss   xmm4, xmm2
        call    atan2_turns             ; (dy, dx)
        movss   xmm5, xmm0
%endmacro

tunnel_start:
        call    tunnel_consts
        mov     edi, 0                  ; byte offset into both tables
        xor     esi, esi
.row:   xor     ebx, ebx
.px:    POLAR
        mov     eax, [BUF1]
        movss   [eax+edi], xmm4         ; depth
        mov     eax, [BUF2]
        movss   [eax+edi], xmm5         ; angle
        add     edi, 4
        inc     ebx
        cmp     ebx, [W]
        jl      .px
        inc     esi
        cmp     esi, [H]
        jl      .row
        ret

; SHADE: xmm4 = depth, xmm5 = angle -> eax = colour (clobbers edx, xmm0-1)
%macro SHADE 0
        addss   xmm4, [T_ADV]           ; u: scroll towards the viewer
        movss   xmm0, xmm4              ; rings along the depth axis
        mulss   xmm0, [f32_0_16]
        SIN01   xmm0
        mulss   xmm5, [f32_12]          ; spokes that twist as they recede:
        movss   xmm1, xmm4              ; twist = v*12 + u*0.09 + spin
        mulss   xmm1, [f32_0_09]
        addss   xmm5, xmm1
        addss   xmm5, [T_SPIN]
        movss   xmm1, xmm5
        SIN01   xmm1
        mulss   xmm0, [f32_0_55]        ; val = ring*0.55 + spoke*0.45
        mulss   xmm1, [f32_0_45]
        addss   xmm0, xmm1
        movss   xmm1, xmm4              ; the brick checker:
        mulss   xmm1, [f32_0_32]        ; (int(u*0.32) + int(twist)) & 1
        cvttss2si eax, xmm1
        cvttss2si edx, xmm5
        add     eax, edx
        test    eax, 1
        jz      %%lit
        xorps   xmm0, [sign32]          ; val = -val*0.7
        mulss   xmm0, [f32_0_7]
%%lit:  mulss   xmm4, [f32_0_02]        ; fog = 1/(1 + u*0.02)
        addss   xmm4, [f32_one]
        movss   xmm1, [f32_one]
        divss   xmm1, xmm4
        mulss   xmm0, [f32_half]        ; lum = (val*0.5 + 0.5)*fog
        addss   xmm0, [f32_half]
        mulss   xmm0, xmm1
        mulss   xmm0, [f32_300]
        cvttss2si eax, xmm0
        cmp     eax, 255
        cmovg   eax, [c255]
        test    eax, eax
        cmovs   eax, [zero]
        mov     eax, [ice+eax*4]
%endmacro

tunnel_render:
        call    tunnel_consts
        cmp     dword [STEP], 1
        je      tunnel_direct
        mov     esi, [BUF1]
        mov     ebx, [BUF2]
        mov     edi, [FB]
        xor     ecx, ecx
; @excerpt TUNNEL
        ; the tables are laid out like the framebuffer: one index, ecx,
        ; walks depth (esi), angle (ebx) and the pixels (edi)
.px:    movss   xmm4, [esi+ecx*4]
        movss   xmm5, [ebx+ecx*4]
        SHADE
        mov     [edi+ecx*4], eax
        inc     ecx
        cmp     ecx, [N]
        jl      .px
; @end
        ret

; tunnel_direct, rung 1: no tables, a square root, a division and an atan2
; per pixel, every frame, for values that never change
tunnel_direct:
        mov     edi, [FB]
        xor     esi, esi
; @excerpt TUNNEL/1
.row:   xor     ebx, ebx
.px:    POLAR                           ; sqrtss, divss, call atan2_turns
        SHADE
        mov     [edi], eax
        add     edi, 4
        inc     ebx
        cmp     ebx, [W]
        jl      .px
        inc     esi
        cmp     esi, [H]
        jl      .row
; @end
        ret

align 16
sign32:    dd 0x80000000, 0, 0, 0
f32_one:   dd 1.0
f32_8192:  dd 8192.0
f32_2_2:   dd 2.2
f32_0_02:  dd 0.02
f32_3:     dd 3.0
f32_0_25:  dd 0.25
f32_0_16:  dd 0.16
f32_12:    dd 12.0
f32_0_09:  dd 0.09
f32_0_55:  dd 0.55
f32_0_45:  dd 0.45
f32_0_32:  dd 0.32
f32_0_7:   dd 0.7
f32_300:   dd 300.0
