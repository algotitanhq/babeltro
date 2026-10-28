; mandelbrot: a dive into the boundary that never ends. The most expensive
; scene in the demo, so it renders on a coarse grid of square blocks. The
; maths is f64 throughout, as in Go: SSE2's sd instructions, round once.

M_STEP  equ SCRAT+0             ; block size in pixels
M_FN    equ SCRAT+4             ; the iteration routine for this rung
M_MAX   equ SCRAT+8             ; iteration budget
M_YE    equ SCRAT+12            ; last row of the block, plus one
M_X0    equ SCRAT+16            ; f64: plane coordinates of pixel (0, 0)
M_Y0    equ SCRAT+24
M_D     equ SCRAT+32            ; f64: plane units per pixel
M_K     equ SCRAT+40
M_SPAN  equ SCRAT+48
M_CY    equ SCRAT+56

mandel_start:
        mov     eax, 2                  ; constant block size in screen terms
        cmp     dword [W], 1600
        jle     .small
        mov     eax, 3
.small: mov     [M_STEP], eax
        ret

; @excerpt MANDELBROT/2
; mandel_iter (xmm4 = cx, xmm5 = cy, ecx = max) -> eax = iterations.
; First the cheap closed-form tests for the main cardioid and the period-2
; bulb, where every point would run the full budget; then the plain loop.
mandel_iter:
        movsd   xmm0, xmm4
        subsd   xmm0, [f64_0_25]        ; x = cx - 0.25
        movsd   xmm1, xmm5
        mulsd   xmm1, xmm5              ; y2 = cy*cy
        movsd   xmm2, xmm0
        mulsd   xmm2, xmm0
        addsd   xmm2, xmm1              ; q = x*x + y2
        movsd   xmm3, xmm2
        addsd   xmm3, xmm0
        mulsd   xmm3, xmm2              ; q*(q + x)
        movsd   xmm6, xmm1
        mulsd   xmm6, [f64_0_25]
        comisd  xmm3, xmm6              ; <= 0.25*y2: in the cardioid
        jbe     .inside
        movsd   xmm0, xmm4
        addsd   xmm0, [f64_one]
        mulsd   xmm0, xmm0
        addsd   xmm0, xmm1              ; (cx+1)^2 + y2 <= 1/16: in the bulb
        comisd  xmm0, [f64_0_0625]
        jbe     .inside
        jmp     mandel_plain
.inside:
        mov     eax, ecx
        ret
; @end

; @excerpt MANDELBROT/1
; mandel_plain (xmm4 = cx, xmm5 = cy, ecx = max) -> eax: the escape-time
; loop and nothing else. The squares stay in registers: each is used twice.
;   xmm0 = zx, xmm1 = zy, xmm2 = zx^2, xmm3 = zy^2
mandel_plain:
        xorpd   xmm0, xmm0
        xorpd   xmm1, xmm1
        xorpd   xmm2, xmm2
        xorpd   xmm3, xmm3
        xor     eax, eax
.iter:  movsd   xmm6, xmm0
        addsd   xmm6, xmm6              ; 2*zx, exactly
        mulsd   xmm6, xmm1
        addsd   xmm6, xmm5
        movsd   xmm1, xmm6              ; zy = 2*zx*zy + cy
        movsd   xmm0, xmm2
        subsd   xmm0, xmm3
        addsd   xmm0, xmm4              ; zx = zx^2 - zy^2 + cx
        movsd   xmm2, xmm0
        mulsd   xmm2, xmm0
        movsd   xmm3, xmm1
        mulsd   xmm3, xmm1
        movsd   xmm6, xmm2
        addsd   xmm6, xmm3
        comisd  xmm6, [f64_4]           ; |z|^2 > 4: escaped after eax steps
        ja      .out
        inc     eax
        cmp     eax, ecx
        jl      .iter
.out:   ret
; @end

mandel_render:
        mov     dword [M_FN], mandel_iter
        mov     eax, [STEP]
        cmp     eax, 1
        jne     .not1
        mov     dword [M_FN], mandel_plain
.not1:  test    eax, eax
        jz      .camera
        mov     dword [M_STEP], 1       ; rungs 1 and 2: every pixel
.camera:
        movsd   xmm7, [BEAT]            ; u = min(t, 14)/12
        minsd   xmm7, [f64_14]
        divsd   xmm7, [f64_12]
        movsd   xmm0, xmm7              ; k = 1 - exp(-8u): the centre
        mulsd   xmm0, [f64_m8]          ; slides onto the target quickly
        call    exp64
        movsd   xmm1, [f64_one]
        subsd   xmm1, xmm0
        movsd   [M_K], xmm1
        movsd   xmm0, xmm7              ; span = 2.9*exp(-u*u*3.6): the dive
        xorpd   xmm0, [sign64]
        mulsd   xmm0, xmm7
        mulsd   xmm0, [f64_3_6]
        call    exp64
        mulsd   xmm0, [f64_2_9]
        movsd   [M_SPAN], xmm0
        mulsd   xmm7, [f64_128]         ; max = 64 + int(128u)
        cvttsd2si eax, xmm7
        add     eax, 64
        mov     [M_MAX], eax
        movsd   xmm0, [M_K]             ; the seahorse valley
        movsd   xmm1, xmm0
        mulsd   xmm0, [f64_ccx]
        addsd   xmm0, [f64_mhalf]       ; ccx = -0.5 + (-0.7436.. + 0.5)*k
        mulsd   xmm1, [f64_ccy]         ; ccy = 0.1318..*k
        cvtsi2sd xmm2, [H]
        cvtsi2sd xmm3, [W]
        divsd   xmm2, xmm3              ; asp = h/w
        movsd   xmm4, [M_SPAN]
        mulsd   xmm4, [f64_half]
        movsd   xmm5, xmm0
        subsd   xmm5, xmm4
        movsd   [M_X0], xmm5            ; x0 = ccx - span*0.5
        mulsd   xmm4, xmm2
        subsd   xmm1, xmm4
        movsd   [M_Y0], xmm1            ; y0 = ccy - span*0.5*asp
        movsd   xmm4, [M_SPAN]
        divsd   xmm4, xmm3
        movsd   [M_D], xmm4             ; d = span/w

        xor     esi, esi                ; by
; @excerpt MANDELBROT
.brow:  cvtsi2sd xmm5, esi
        mulsd   xmm5, [M_D]
        addsd   xmm5, [M_Y0]
        movsd   [M_CY], xmm5            ; cy = y0 + by*d
        mov     eax, esi
        add     eax, [M_STEP]
        cmp     eax, [H]
        cmovg   eax, [H]
        mov     [M_YE], eax             ; the block's rows: by .. min(by+step, h)
        xor     ebx, ebx                ; bx
.block: cvtsi2sd xmm4, ebx
        mulsd   xmm4, [M_D]
        addsd   xmm4, [M_X0]            ; cx = x0 + bx*d
        movsd   xmm5, [M_CY]
        mov     ecx, [M_MAX]
        call    [M_FN]                  ; eax = iterations
        cmp     eax, [M_MAX]
        jl      .escaped
        mov     eax, 0xFF0A0812         ; inside the set
        jmp     .paint
.escaped:
        cvtsi2sd xmm0, eax              ; v = min(sqrt(it/40), 1): the ramp
        divsd   xmm0, [f64_40]          ; is anchored to a fixed count, so a
        sqrtsd  xmm0, xmm0              ; bigger budget does not darken it
        minsd   xmm0, [f64_one]
        mulsd   xmm0, [f64_0_92]        ; the palette at v*0.92 + 0.04
        addsd   xmm0, [f64_0_04]
        mulsd   xmm0, [f64_255]
        cvttsd2si eax, xmm0
        test    eax, eax
        cmovs   eax, [zero]
        cmp     eax, 255
        cmovg   eax, [c255]
        mov     eax, [ice+eax*4]
.paint: mov     edx, ebx                ; fill the block, row by row, with
        add     edx, [M_STEP]           ; rep stosd: eax to [edi], ecx times
        cmp     edx, [W]
        cmovg   edx, [W]
        sub     edx, ebx                ; block width
        mov     ebp, esi
.frow:  mov     edi, ebp
        imul    edi, [W]
        add     edi, ebx
        shl     edi, 2
        add     edi, [FB]
        mov     ecx, edx
        rep stosd
        inc     ebp
        cmp     ebp, [M_YE]
        jl      .frow
        add     ebx, [M_STEP]
        cmp     ebx, [W]
        jl      .block
        add     esi, [M_STEP]
        cmp     esi, [H]
        jl      .brow
; @end
        ret

align 8
f64_0_25:   dq 0.25
f64_0_0625: dq 0.0625
f64_4:      dq 4.0
f64_14:     dq 14.0
f64_12:     dq 12.0
f64_m8:     dq -8.0
f64_3_6:    dq 3.6
f64_2_9:    dq 2.9
f64_128:    dq 128.0
f64_ccx:    dq -0.243643887037151   ; -0.743643887037151 + 0.5, exact
f64_mhalf:  dq -0.5
f64_ccy:    dq 0.131825904205330
f64_40:     dq 40.0
f64_0_92:   dq 0.92
f64_0_04:   dq 0.04
