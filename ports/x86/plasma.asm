; plasma: four summed sine fields, the oldest trick in the demoscene book.
; Done naively it is four sines per pixel (rungs 1 and 2); the default rung
; moves three of the four into 1D tables rebuilt once per frame, leaving a
; single table lookup per pixel.

; SIN xmm: fmath.Sin from the table, in place (clobbers eax)
%macro SIN 1
        mulss   %1, [inv2pi]
        cvttss2si eax, %1
        and     eax, 8191
        movss   %1, [sintab+eax*4]
%endmacro

; plasma state, after the shared variables
P_KX    equ SCRAT+0
P_KY    equ SCRAT+4
P_KR    equ SCRAT+8
P_CX    equ SCRAT+12
P_CY    equ SCRAT+16
P_T13   equ SCRAT+20
P_T11   equ SCRAT+24
P_T08   equ SCRAT+28

; plasma_start: the distance of every pixel to the centre, scaled. Built
; once per size; sqrtss is correctly rounded, so it is Go's Sqrt exactly.
plasma_start:
        call    plasma_consts
        movss   xmm5, [P_KR]
        mov     edi, [RAD]
        xor     edx, edx                ; y
.row:   cvtsi2ss xmm4, edx
        subss   xmm4, [P_CY]
        mulss   xmm4, xmm4              ; dy*dy
        xor     ecx, ecx                ; x
.px:    cvtsi2ss xmm0, ecx
        subss   xmm0, [P_CX]
        mulss   xmm0, xmm0              ; dx*dx
        addss   xmm0, xmm4
        sqrtss  xmm0, xmm0
        mulss   xmm0, xmm5
        movss   [edi], xmm0
        add     edi, 4
        inc     ecx
        cmp     ecx, [W]
        jl      .px
        inc     edx
        cmp     edx, [H]
        jl      .row
        ret

; plasma_consts: kx = 26/w, ky = 26/h, kr = 44/(w+h), the centre, and the
; three time offsets and the phase, all f32
plasma_consts:
        cvtsi2ss xmm1, [W]
        movss   xmm0, [f32_26]
        divss   xmm0, xmm1
        movss   [P_KX], xmm0
        mulss   xmm1, [f32_half]
        movss   [P_CX], xmm1
        cvtsi2ss xmm1, [H]
        movss   xmm0, [f32_26]
        divss   xmm0, xmm1
        movss   [P_KY], xmm0
        mulss   xmm1, [f32_half]
        movss   [P_CY], xmm1
        mov     eax, [W]
        add     eax, [H]
        cvtsi2ss xmm1, eax
        movss   xmm0, [f32_44]
        divss   xmm0, xmm1
        movss   [P_KR], xmm0
        movss   xmm7, [TIME]
        movss   xmm0, xmm7
        mulss   xmm0, [f32_1_3]
        movss   [P_T13], xmm0
        movss   xmm0, xmm7
        mulss   xmm0, [f32_1_1]
        movss   [P_T11], xmm0
        movss   xmm0, xmm7
        mulss   xmm0, [f32_0_8]
        movss   [P_T08], xmm0
        mulss   xmm7, [f32_2_6]
        movss   [PHASE], xmm7
        ret

; PIXEL: xmm4 = v, the sum of the four sines, to a palette index clamped
; to 0..255 (cmov: no branch), then the colour into [edi]
%macro PIXEL 0
        mulss   xmm4, [f32_36]
        addss   xmm4, [f32_127_5]
        cvttss2si eax, xmm4             ; int(v*36 + 127.5)
        test    eax, eax
        cmovs   eax, [zero]             ; below 0: 0
        cmp     eax, 255
        cmovg   eax, [c255]             ; above 255: 255
        mov     eax, [sunset+eax*4]
        mov     [edi], eax
%endmacro

plasma_render:
        call    plasma_consts
        mov     eax, [STEP]
        cmp     eax, 1
        je      plasma_sin
        cmp     eax, 2
        je      plasma_table

        ; the three 1D tables: per column, per row, per diagonal
        movss   xmm5, [P_KX]
        mov     edi, [SX]
        xor     ecx, ecx
.sx:    cvtsi2ss xmm0, ecx              ; sin(x*kx + t*1.3)
        mulss   xmm0, xmm5
        addss   xmm0, [P_T13]
        SIN     xmm0
        movss   [edi+ecx*4], xmm0
        inc     ecx
        cmp     ecx, [W]
        jl      .sx
        mov     edi, [SY]
        xor     ecx, ecx
.sy:    cvtsi2ss xmm0, ecx              ; sin(y*ky*1.35 - t*1.1)
        mulss   xmm0, [P_KY]
        mulss   xmm0, [f32_1_35]
        subss   xmm0, [P_T11]
        SIN     xmm0
        movss   [edi+ecx*4], xmm0
        inc     ecx
        cmp     ecx, [H]
        jl      .sy
        mov     edx, [W]
        add     edx, [H]
        mov     edi, [SXY]
        xor     ecx, ecx
.sxy:   cvtsi2ss xmm0, ecx              ; sin(i*kx*0.85 + t*0.8)
        mulss   xmm0, xmm5
        mulss   xmm0, [f32_0_85]
        addss   xmm0, [P_T08]
        SIN     xmm0
        movss   [edi+ecx*4], xmm0
        inc     ecx
        cmp     ecx, edx
        jl      .sxy

        movss   xmm6, [PHASE]
        mov     ebp, [SX]
        mov     esi, [RAD]
        mov     ebx, [SXY]
        mov     edi, [FB]
        xor     edx, edx
; @excerpt PLASMA
        ; ebp = sx[], esi = rad row, ebx = sxy + y, edi = pixel, edx = y
.row:   mov     eax, [SY]
        movss   xmm7, [eax+edx*4]       ; sy: one value for the whole row
        xor     ecx, ecx                ; x
.px:    movss   xmm4, [ebp+ecx*4]       ; sx[x]
        addss   xmm4, xmm7              ;  + sy
        addss   xmm4, [ebx+ecx*4]       ;  + sxy[x + y]
        movss   xmm1, [esi+ecx*4]       ; the one sine left: rad[x] + phase
        addss   xmm1, xmm6
        mulss   xmm1, [inv2pi]          ; radians to table steps
        cvttss2si eax, xmm1             ; truncate toward zero, like Go
        and     eax, 8191               ; wrap around the circle
        addss   xmm4, [sintab+eax*4]    ;  + sin(rad + phase)
        PIXEL                           ; index, clamp, palette, store
        add     edi, 4
        inc     ecx
        cmp     ecx, [W]
        jl      .px
        lea     esi, [esi+ecx*4]        ; next rad row
        add     ebx, 4                  ; the diagonal slides by one
        inc     edx
        cmp     edx, [H]
        jl      .row
; @end
        ret

; sin32 (xmm0) -> xmm0: the "maths library" sine, f32 in, f64 inside,
; rounded back to f32, as Go's float32(math.Sin(float64(a)))
sin32:
        cvtss2sd xmm0, xmm0
        call    sin64
        cvtsd2ss xmm0, xmm0
        ret

; plasma_sin, rung 1: every term, every pixel, a real sine call.
; ebx = x, esi = y, edi = pixel: sin64 leaves them alone.
plasma_sin:
        mov     edi, [FB]
        xor     esi, esi
; @excerpt PLASMA/1
.row:   cvtsi2ss xmm7, esi
        subss   xmm7, [P_CY]
        mulss   xmm7, xmm7              ; dy*dy
        xor     ebx, ebx
.px:    cvtsi2ss xmm0, ebx              ; sin(x*kx + t*1.3)
        mulss   xmm0, [P_KX]
        addss   xmm0, [P_T13]
        call    sin32
        movss   xmm4, xmm0
        cvtsi2ss xmm0, esi              ; sin(y*ky*1.35 - t*1.1)
        mulss   xmm0, [P_KY]
        mulss   xmm0, [f32_1_35]
        subss   xmm0, [P_T11]
        call    sin32
        addss   xmm4, xmm0
        lea     eax, [ebx+esi]          ; sin((x+y)*kx*0.85 + t*0.8)
        cvtsi2ss xmm0, eax
        mulss   xmm0, [P_KX]
        mulss   xmm0, [f32_0_85]
        addss   xmm0, [P_T08]
        call    sin32
        addss   xmm4, xmm0
        cvtsi2ss xmm0, ebx              ; sin(sqrt(dx*dx + dy*dy)*kr + phase)
        subss   xmm0, [P_CX]
        mulss   xmm0, xmm0
        addss   xmm0, xmm7
        sqrtss  xmm0, xmm0
        mulss   xmm0, [P_KR]
        addss   xmm0, [PHASE]
        call    sin32
        addss   xmm4, xmm0
        PIXEL
        add     edi, 4
        inc     ebx
        cmp     ebx, [W]
        jl      .px
        inc     esi
        cmp     esi, [H]
        jl      .row
; @end
        ret

; plasma_table, rung 2: the same loop, each sine call now a table lookup
plasma_table:
        mov     edi, [FB]
        xor     esi, esi
; @excerpt PLASMA/2
.row:   cvtsi2ss xmm7, esi
        subss   xmm7, [P_CY]
        mulss   xmm7, xmm7              ; dy*dy
        xor     ebx, ebx
.px:    cvtsi2ss xmm0, ebx              ; sin(x*kx + t*1.3)
        mulss   xmm0, [P_KX]
        addss   xmm0, [P_T13]
        SIN     xmm0
        movss   xmm4, xmm0
        cvtsi2ss xmm0, esi              ; sin(y*ky*1.35 - t*1.1)
        mulss   xmm0, [P_KY]
        mulss   xmm0, [f32_1_35]
        subss   xmm0, [P_T11]
        SIN     xmm0
        addss   xmm4, xmm0
        lea     eax, [ebx+esi]          ; sin((x+y)*kx*0.85 + t*0.8)
        cvtsi2ss xmm0, eax
        mulss   xmm0, [P_KX]
        mulss   xmm0, [f32_0_85]
        addss   xmm0, [P_T08]
        SIN     xmm0
        addss   xmm4, xmm0
        cvtsi2ss xmm0, ebx              ; sin(sqrt(dx*dx + dy*dy)*kr + phase)
        subss   xmm0, [P_CX]
        mulss   xmm0, xmm0
        addss   xmm0, xmm7
        sqrtss  xmm0, xmm0
        mulss   xmm0, [P_KR]
        addss   xmm0, [PHASE]
        SIN     xmm0
        addss   xmm4, xmm0
        PIXEL
        add     edi, 4
        inc     ebx
        cmp     ebx, [W]
        jl      .px
        inc     esi
        cmp     esi, [H]
        jl      .row
; @end
        ret

align 4
f32_half:  dd 0.5
f32_26:    dd 26.0
f32_44:    dd 44.0
f32_1_3:   dd 1.3
f32_1_1:   dd 1.1
f32_1_35:  dd 1.35
f32_0_85:  dd 0.85
f32_0_8:   dd 0.8
f32_2_6:   dd 2.6
f32_36:    dd 36.0
f32_127_5: dd 127.5
