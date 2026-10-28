; metaballs: sum radial fields and shade the iso-contours. Every pixel
; evaluates sum(r^2/d^2), one division per ball and no square root, and
; the contour band gets a hot rim so the blobs read as liquid.

B_ASP   equ SCRAT+0             ; w/h: a circle in field space stays round
B_KW    equ SCRAT+4             ; (float)w and (float)h
B_KH    equ SCRAT+8

metaballs_render:
        movss   xmm7, [TIME]
        cvtsi2ss xmm0, [W]
        movss   [B_KW], xmm0
        cvtsi2ss xmm1, [H]
        movss   [B_KH], xmm1
        divss   xmm0, xmm1
        movss   [B_ASP], xmm0
        ; each ball orbits on its own ellipse and breathes: its centre and
        ; squared radius, once per frame, into balls[i] = (x, y, r^2)
        xor     ebx, ebx
        mov     edi, balls
.ball:  cvtsi2ss xmm6, ebx              ; fi
        movss   xmm5, xmm6              ; a = t*(0.35 + fi*0.07) + fi*2.1
        mulss   xmm5, [f32_0_07]
        addss   xmm5, [f32_0_35]
        mulss   xmm5, xmm7
        movss   xmm1, xmm6
        mulss   xmm1, [f32_2_1]
        addss   xmm5, xmm1
        movss   xmm0, xmm5              ; x = 0.5 + 0.2*cos(a)*(1 + 0.3*sin(t*0.5 + fi))
        COS     xmm0
        mulss   xmm0, [f32_0_2]
        movss   xmm1, xmm7
        mulss   xmm1, [f32_half]
        addss   xmm1, xmm6
        SIN     xmm1
        mulss   xmm1, [f32_0_3]
        addss   xmm1, [f32_one]
        mulss   xmm0, xmm1
        addss   xmm0, [f32_half]
        subss   xmm0, [f32_half]        ; relative to the centre, then
        mulss   xmm0, [B_ASP]           ; stretched by the aspect
        movss   [edi], xmm0
        movss   xmm0, xmm5              ; y = 0.5 + 0.2*sin(a*1.3 + fi)*(1 + 0.3*cos(t*0.4 + fi*2))
        mulss   xmm0, [f32_1_3]
        addss   xmm0, xmm6
        SIN     xmm0
        mulss   xmm0, [f32_0_2]
        movss   xmm1, xmm7
        mulss   xmm1, [f32_0_4]
        movss   xmm2, xmm6
        addss   xmm2, xmm6
        addss   xmm1, xmm2
        COS     xmm1
        mulss   xmm1, [f32_0_3]
        addss   xmm1, [f32_one]
        mulss   xmm0, xmm1
        addss   xmm0, [f32_half]
        subss   xmm0, [f32_half]
        movss   [edi+4], xmm0
        movss   xmm0, xmm7              ; r = 0.105 + 0.025*sin(t*1.1 + fi*1.7)
        mulss   xmm0, [f32_1_1]
        movss   xmm1, xmm6
        mulss   xmm1, [f32_1_7]
        addss   xmm0, xmm1
        SIN     xmm0
        mulss   xmm0, [f32_0_025]
        addss   xmm0, [f32_0_105]
        mulss   xmm0, xmm0
        movss   [edi+8], xmm0
        add     edi, 12
        inc     ebx
        cmp     ebx, 6
        jl      .ball

        mov     edi, [FB]
        xor     esi, esi
; @excerpt METABALLS
.row:   cvtsi2ss xmm4, esi              ; fy = y/h - 0.5
        divss   xmm4, [B_KH]
        subss   xmm4, [f32_half]
        xor     ecx, ecx
.px:    cvtsi2ss xmm2, ecx              ; fx = (x/w - 0.5)*asp
        divss   xmm2, [B_KW]
        subss   xmm2, [f32_half]
        mulss   xmm2, [B_ASP]
        xorps   xmm0, xmm0              ; field
        mov     edx, balls
.sum:   movss   xmm1, xmm2
        subss   xmm1, [edx]             ; dx
        mulss   xmm1, xmm1
        movss   xmm3, xmm4
        subss   xmm3, [edx+4]           ; dy
        mulss   xmm3, xmm3
        addss   xmm1, xmm3
        addss   xmm1, [f32_1e_5]
        movss   xmm3, [edx+8]
        divss   xmm3, xmm1              ; r^2 / (dx*dx + dy*dy + 1e-5)
        addss   xmm0, xmm3
        add     edx, 12
        cmp     edx, balls + 6*12
        jl      .sum
        movss   xmm1, [f32_1_6]         ; v = field/(1.6 + field): 0..1
        addss   xmm1, xmm0              ; without a log
        movss   xmm3, xmm0
        divss   xmm3, xmm1
        mulss   xmm3, [f32_255]
        cvttss2si eax, xmm3
        cmp     eax, 255
        cmovg   eax, [c255]
        comiss  xmm0, [f32_one]         ; the rim: where the balls meet,
        jbe     .paint                  ; 1 < field < 1.09, flares white
        comiss  xmm0, [f32_1_09]
        jae     .paint
        mov     eax, 255
.paint: mov     eax, [sunset+eax*4]
        mov     [edi], eax
        add     edi, 4
        inc     ecx
        cmp     ecx, [W]
        jl      .px
        inc     esi
        cmp     esi, [H]
        jl      .row
; @end
        ret

align 4
f32_0_07:  dd 0.07
f32_2_1:   dd 2.1
f32_0_2:   dd 0.20
f32_0_3:   dd 0.3
f32_0_025: dd 0.025
f32_0_105: dd 0.105
f32_1e_5:  dd 1e-5
f32_1_6:   dd 1.6
f32_1_09:  dd 1.09
