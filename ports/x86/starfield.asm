; starfield: a warp-speed star tunnel. Stars live in 3D, get projected in
; perspective and dragged into short streaks: each star draws from its
; previous depth to its current one, which is what sells the speed.

S_CX    equ SCRAT+0             ; f32 frame constants
S_CY    equ SCRAT+4
S_DZ    equ SCRAT+8
S_ZOOM  equ SCRAT+12
L_X1    equ SCRAT+16            ; the line being drawn
L_Y1    equ SCRAT+20
L_DX    equ SCRAT+24
L_DY    equ SCRAT+28
L_SX    equ SCRAT+32
L_SY    equ SCRAT+36
L_C     equ SCRAT+40

; RNGF xmm: fmath.Rng.Float32, the top 24 bits of the next xorshift32 over
; 2^24: exact in every language (clobbers eax, edx)
%macro RNGF 1
        mov     edx, [RNG]
        XORSHIFT edx
        mov     [RNG], edx
        shr     edx, 8
        cvtsi2ss %1, edx
        mulss   %1, [f32_2m24]
%endmacro

; SPREAD xmm, k: (rand*2 - 1)*k
%macro SPREAD 2
        RNGF    %1
        addss   %1, %1
        subss   %1, [f32_one]
        mulss   %1, [%2]
%endmacro

starfield_start:
        mov     dword [RNG], 0x6005E
        mov     edi, stars
.star:  SPREAD  xmm0, f32_1_6x          ; x, y, z: three draws, in order
        movss   [edi], xmm0
        SPREAD  xmm0, f32_1_6x
        movss   [edi+4], xmm0
        RNGF    xmm0
        mulss   xmm0, [f32_40]
        addss   xmm0, [f32_0_2]
        movss   [edi+8], xmm0
        add     edi, 12
        cmp     edi, stars + 1600*12
        jl      .star
        ; the deep-navy vignette, once per size into BUF1, in f64
        mov     edi, [BUF1]
        cvtsi2sd xmm6, [W]
        cvtsi2sd xmm7, [H]
        xor     esi, esi
.row:   cvtsi2sd xmm5, esi
        divsd   xmm5, xmm7
        subsd   xmm5, [f64_half]
        mulsd   xmm5, xmm5              ; dy*dy
        xor     ebx, ebx
.px:    cvtsi2sd xmm4, ebx
        divsd   xmm4, xmm6
        subsd   xmm4, [f64_half]
        mulsd   xmm4, xmm4
        addsd   xmm4, xmm5              ; v = dx*dx + dy*dy
        movsd   xmm3, xmm4
        mulsd   xmm3, [f64_0_03]
        movsd   xmm0, [f64_0_02]
        subsd   xmm0, xmm3
        movsd   xmm3, xmm0
        maxsd   xmm3, [f64_zero]
        call    to_byte
        mov     [edi], cl
        movsd   xmm3, xmm4
        mulsd   xmm3, [f64_0_025]
        movsd   xmm0, [f64_0_02]
        subsd   xmm0, xmm3
        movsd   xmm3, xmm0
        maxsd   xmm3, [f64_zero]
        call    to_byte
        mov     [edi+1], cl
        movsd   xmm3, xmm4
        mulsd   xmm3, [f64_0_03]
        movsd   xmm0, [f64_0_05]
        subsd   xmm0, xmm3
        movsd   xmm3, xmm0
        maxsd   xmm3, [f64_zero]
        call    to_byte
        mov     [edi+2], cl
        mov     byte [edi+3], 0xFF
        add     edi, 4
        inc     ebx
        cmp     ebx, [W]
        jl      .px
        inc     esi
        cmp     esi, [H]
        jl      .row
        ret

; PROJECT x, f -> eax = int(c + x*f*zoom)
%macro PROJECT 3
        movss   xmm2, %1
        mulss   xmm2, %2
        mulss   xmm2, [S_ZOOM]
        addss   xmm2, [%3]
        cvttss2si eax, xmm2
%endmacro

starfield_render:
        cvtsi2ss xmm0, [W]
        movss   xmm1, xmm0
        mulss   xmm0, [f32_half]
        movss   [S_CX], xmm0
        mulss   xmm1, [f32_0_78]
        movss   [S_ZOOM], xmm1          ; zoom = w*0.78
        cvtsi2ss xmm0, [H]
        mulss   xmm0, [f32_half]
        movss   [S_CY], xmm0
        movsd   xmm0, [BEAT]            ; speed = 2.5 + min(t, 3)*4: the
        minsd   xmm0, [f64_3]           ; entry has a kick
        mulsd   xmm0, [f64_4]
        addsd   xmm0, [f64_2_5]
        cvtsd2ss xmm0, xmm0
        mulss   xmm0, [f32_dt]          ; dz = speed*dt
        movss   [S_DZ], xmm0
        mov     esi, stars
        mov     edi, streaks
; @excerpt STARFIELD
.star:  movss   xmm7, [esi+8]           ; z -= dz
        subss   xmm7, [S_DZ]
        movss   xmm5, [esi]             ; x
        movss   xmm6, [esi+4]           ; y
        comiss  xmm7, [f32_0_8]
        jae     .seen
        addss   xmm7, [f32_40]          ; passed the camera: respawn far away
        SPREAD  xmm5, f32_1_1x
        SPREAD  xmm6, f32_1_1x
        movss   [esi], xmm5
        movss   [esi+4], xmm6
.seen:  movss   [esi+8], xmm7
        movss   xmm3, [f32_one]         ; project now, and a little deeper:
        divss   xmm3, xmm7              ; the streak between the two
        PROJECT xmm5, xmm3, S_CX
        mov     [edi], eax              ; x0
        PROJECT xmm6, xmm3, S_CY
        mov     [edi+4], eax            ; y0
        movss   xmm4, [S_DZ]
        mulss   xmm4, [f32_2_4]
        addss   xmm4, xmm7
        movss   xmm3, [f32_one]
        divss   xmm3, xmm4              ; f2 = 1/(z + dz*2.4)
        PROJECT xmm5, xmm3, S_CX
        mov     [edi+8], eax            ; x1
        PROJECT xmm6, xmm3, S_CY
        mov     [edi+12], eax           ; y1
        divss   xmm7, [f32_40]          ; brighter and bluer as it gets close:
        movss   xmm0, [f32_one]         ; b = (1 - z/40)^2
        subss   xmm0, xmm7
        mulss   xmm0, xmm0
        movss   xmm1, xmm0              ; blue = 255*(0.25 + 0.75*b)
        mulss   xmm1, [f32_0_75]
        addss   xmm1, [f32_0_25]
        mulss   xmm1, [f32_255]
        cvttss2si edx, xmm1
        shl     edx, 8
        movss   xmm1, xmm0              ; green = 190*b + 40
        mulss   xmm1, [f32_190]
        addss   xmm1, [f32_40]
        cvttss2si eax, xmm1
        or      edx, eax
        shl     edx, 8
        mulss   xmm0, [f32_120]         ; red = 120*b + 40
        addss   xmm0, [f32_40]
        cvttss2si eax, xmm0
        or      edx, eax
        or      edx, 0xFF000000
        mov     [edi+16], edx
        add     esi, 12
        add     edi, 20
        cmp     esi, stars + 1600*12
        jl      .star
; @end
        mov     esi, [BUF1]             ; the backdrop: one string move
        mov     edi, [FB]
        mov     ecx, [N]
        rep movsd
        mov     esi, streaks
.draw:  mov     ebx, [esi]
        mov     ecx, [esi+4]
        mov     eax, [esi+8]
        mov     [L_X1], eax
        mov     eax, [esi+12]
        mov     [L_Y1], eax
        mov     eax, [esi+16]
        mov     [L_C], eax
        call    line_add
        mov     eax, [esi+8]            ; the bright head pixel
        mov     ecx, [esi+12]
        cmp     eax, 0
        jl      .next
        cmp     eax, [W]
        jge     .next
        cmp     ecx, 0
        jl      .next
        cmp     ecx, [H]
        jge     .next
        imul    ecx, [W]
        add     ecx, eax
        mov     eax, [FB]
        mov     dword [eax+ecx*4], 0xFFCCEEFF
.next:  add     esi, 20
        cmp     esi, streaks + 1600*20
        jl      .draw
        ret

; ADDC k: saturating add of byte k of the colour into byte k of [edi]
%macro ADDC 1
        movzx   eax, byte [edi+%1]
        movzx   ebp, byte [L_C+%1]
        add     eax, ebp
        cmp     eax, 255
        cmovg   eax, [c255]
        mov     [edi+%1], al
%endmacro

; line_add (ebx = x0, ecx = y0, [L_X1], [L_Y1], [L_C]): Bresenham, adding
; the colour so overlapping stars accumulate. edx = err.
line_add:
        mov     eax, [L_X1]             ; dx = |x1 - x0|
        sub     eax, ebx
        mov     ebp, eax
        neg     eax
        cmovl   eax, ebp
        mov     [L_DX], eax
        mov     eax, [L_Y1]             ; dy = -|y1 - y0|
        sub     eax, ecx
        mov     ebp, eax
        neg     ebp
        cmovle  ebp, eax
        neg     ebp
        mov     [L_DY], ebp
        mov     eax, 1                  ; sx, sy = +1 or -1
        mov     ebp, -1
        cmp     ebx, [L_X1]
        cmovge  eax, ebp
        mov     [L_SX], eax
        mov     eax, 1
        cmp     ecx, [L_Y1]
        cmovge  eax, ebp
        mov     [L_SY], eax
        mov     edx, [L_DX]             ; err = dx + dy
        add     edx, [L_DY]
.step:  cmp     ebx, 0                  ; on screen? then add the colour
        jl      .skip
        cmp     ebx, [W]
        jge     .skip
        cmp     ecx, 0
        jl      .skip
        cmp     ecx, [H]
        jge     .skip
        mov     edi, ecx
        imul    edi, [W]
        add     edi, ebx
        shl     edi, 2
        add     edi, [FB]
        ADDC    0
        ADDC    1
        ADDC    2
        mov     byte [edi+3], 0xFF
.skip:  cmp     ebx, [L_X1]
        jne     .more
        cmp     ecx, [L_Y1]
        je      .done
.more:  lea     eax, [edx+edx]          ; e2 = 2*err
        cmp     eax, [L_DY]
        jl      .noy
        add     edx, [L_DY]
        add     ebx, [L_SX]
.noy:   cmp     eax, [L_DX]
        jg      .step
        add     edx, [L_DX]
        add     ecx, [L_SY]
        jmp     .step
.done:  ret

align 8
f64_0_02:  dq 0.02
f64_0_025: dq 0.025
f64_2_5:   dq 2.5
f32_2m24:  dd 0x33800000            ; 1/16777216
f32_1_6x:  dd 1.6
f32_1_1x:  dd 1.1
f32_40:    dd 40.0
f32_0_78:  dd 0.78
f32_2_4:   dd 2.4
f32_190:   dd 190.0
f32_120:   dd 120.0
f32_dt:    dd 0x3C888889            ; (float)(1.0/60)
