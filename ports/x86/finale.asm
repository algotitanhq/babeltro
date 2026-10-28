; finale: the closing card. The logo, its reflection, the subtitle and the
; numbers that make the point, over a glowing backdrop with a few twinkling
; stars. Everything is drawn from the 5x7 font in font.asm, block by block.

%ifndef LANG
%define LANG 'X86'              ; the only words that differ between ports
%endif
%strlen LANG_LEN LANG

absolute 0x31100
F_SUBS:   resd 1        ; layout, computed by finale_start
F_STATS:  resd 1
F_GAPS:   resd 1        ; stat_gap
F_TAGS:   resd 1
F_LOGOS:  resd 1
F_LOGOX:  resd 1
F_LOGOY:  resd 1
F_TEXTH:  resd 1
F_REFLH:  resd 1
F_FLOORY: resd 1
F_SUBX:   resd 1
F_SUBY:   resd 1
F_STATSY: resd 1
F_TAGX:   resd 1
F_TAGY:   resd 1
F_FIXED:  resd 1
F_TOP:    resd 1
F_BOTTOM: resd 1
F_GAP:    resd 1
F_BX0:    resd 1        ; the rectangle the glow can reach
F_BX1:    resd 1
F_BY0:    resd 1
F_BY1:    resd 1
F_GX:     resd 1        ; f32 glow centre and radius
F_GY:     resd 1
F_GR:     resd 1
F_PULSE:  resd 1
F_I:      resd 1        ; loop counters that survive calls
F_J:      resd 1
F_OFFS:   resd 8        ; per-letter bounce
T_STR:    resd 1        ; text: what to draw and how
T_LEN:    resd 1
T_X:      resd 1
T_Y:      resd 1
X_SCALE:  resd 1
T_FN:     resd 1        ; block handler: fill_solid, fill_gradient, fill_reflect
T_REFL:   resd 1        ; 1: mirror the rows about T_Y
T_OFFP:   resd 1        ; pointer to per-letter offsets, or 0
T_C:      resd 1        ; solid colour
T_I:      resd 1
G_PTR:    resd 1        ; the glyph being walked
G_X:      resd 1
G_Y:      resd 1
G_DIR:    resd 1        ; +scale per row, or -scale for the reflection
G_ROW:    resd 1
G_COL:    resd 1
G_BITS:   resd 1
B_X0:     resd 1        ; the clipped block a handler fills
B_X1:     resd 1
B_Y0:     resd 1
B_Y1:     resd 1
L_A:      resd 1        ; lerp_rgb's two colours and its result
L_B:      resd 1
L_OUT:    resd 1
A_C:      resd 1        ; canvas_additive's colour and intensity
A_I:      resd 1

section .text

TOP_C   equ 0xFFFFF6E8          ; pale cream
MID_C   equ 0xFF7C9CFF          ; hot rose
BOT_C   equ 0xFF582080          ; deep violet

; SDIV k: eax = eax / k, truncated toward zero like C and Go (clobbers edx)
%macro SDIV 1
        cdq
        idiv    dword [%1]
%endmacro

; HALF: eax / 2 toward zero, the classic way: add the sign bit, shift
%macro HALF 0
        cdq
        sub     eax, edx
        sar     eax, 1
%endmacro

; WIDTH len, scale -> eax = text_width: (len*6 - 1)*scale
%macro WIDTH 2
        mov     eax, %1
        imul    eax, eax, 6
        dec     eax
        imul    eax, %2
%endmacro

finale_start:
        mov     dword [RNG], 0xF1A1E    ; background stars: three draws each
        mov     edi, stars
.star:  RNGF    xmm0
        movss   [edi], xmm0
        RNGF    xmm0
        movss   [edi+4], xmm0
        RNGF    xmm0
        mulss   xmm0, [f32_0_85]
        addss   xmm0, [f32_0_15]
        movss   [edi+8], xmm0
        add     edi, 12
        cmp     edi, stars + 260*12
        jl      .star

        mov     eax, [W]                ; sub_scale = max(w/300, 1)
        SDIV    k_300
        mov     ecx, 1
        cmp     eax, ecx
        cmovl   eax, ecx
        mov     [F_SUBS], eax
        mov     eax, [W]                ; stats_scale = max(w/440, 1)
        SDIV    k_440
        cmp     eax, ecx
        cmovl   eax, ecx
        mov     [F_STATS], eax
        lea     ecx, [eax+1]
        mov     [F_TAGS], ecx           ; tag_scale = stats_scale + 1
        imul    eax, eax, 21            ; stat_gap = 7*stats_scale*3/2
        SDIV    k_2
        mov     [F_GAPS], eax
        mov     eax, [H]
        SDIV    k_48
        mov     [F_GAP], eax            ; gap = h/48
        mov     eax, [H]
        SDIV    k_40
        mov     [F_TOP], eax            ; top = h/40
        cvtsi2ss xmm0, [H]
        mulss   xmm0, [f32_0_90]
        cvttss2si eax, xmm0
        mov     [F_BOTTOM], eax         ; bottom = h*0.90
        mov     eax, [F_SUBS]           ; fixed = sub_h + 3*stat_gap + tag_h
        imul    eax, eax, 7             ;         + 4*gap: all but the wordmark
        mov     ecx, [F_GAPS]
        lea     ecx, [ecx+ecx*2]
        add     eax, ecx
        mov     ecx, [F_TAGS]
        imul    ecx, ecx, 7
        add     eax, ecx
        mov     ecx, [F_GAP]
        lea     eax, [eax+ecx*4]
        mov     [F_FIXED], eax
        mov     eax, [F_BOTTOM]         ; the wordmark takes the room left:
        sub     eax, [F_TOP]            ; 10.5 blocks with its reflection
        sub     eax, [F_FIXED]
        add     eax, eax
        SDIV    k_21
        mov     ebx, eax
        mov     eax, [W]                ; and never more than 45% of the width
        imul    eax, eax, 9
        SDIV    k_20
        mov     ecx, LANG_LEN*6 - 1
        mov     [F_I], ecx
        SDIV    F_I
        cmp     ebx, eax
        cmovg   ebx, eax
        mov     eax, 3
        cmp     ebx, eax
        cmovl   ebx, eax
        mov     [F_LOGOS], ebx
        imul    eax, ebx, 7
        mov     [F_TEXTH], eax          ; text_h = 7*scale
        HALF
        mov     [F_REFLH], eax          ; refl_h = text_h/2
        WIDTH   LANG_LEN, ebx
        mov     ecx, eax
        mov     eax, [W]
        sub     eax, ecx
        HALF
        mov     [F_LOGOX], eax          ; logo_x = (w - logo_w)/2
        mov     eax, [F_BOTTOM]         ; logo_y = top + (bottom - top
        sub     eax, [F_TOP]            ;          - block_h)/2
        sub     eax, [F_TEXTH]
        sub     eax, [F_REFLH]
        sub     eax, [F_FIXED]
        HALF
        add     eax, [F_TOP]
        mov     [F_LOGOY], eax
        add     eax, [F_TEXTH]
        mov     [F_FLOORY], eax         ; floor_y = logo_y + text_h
        add     eax, [F_REFLH]
        add     eax, [F_GAP]
        mov     [F_SUBY], eax           ; sub_y = floor_y + refl_h + gap
        mov     ecx, [F_SUBS]
        imul    ecx, ecx, 7
        add     eax, ecx
        add     eax, [F_GAP]
        mov     [F_STATSY], eax         ; stats_y = sub_y + sub_h + gap
        mov     ecx, [F_GAPS]
        lea     ecx, [ecx+ecx*2]
        add     eax, ecx
        add     eax, [F_GAP]
        mov     [F_TAGY], eax           ; tag_y = stats_y + 3*stat_gap + gap
        WIDTH   sub_len, [F_SUBS]
        mov     ecx, eax
        mov     eax, [W]
        sub     eax, ecx
        HALF
        mov     [F_SUBX], eax
        WIDTH   tag_len, [F_TAGS]
        mov     ecx, eax
        mov     eax, [W]
        sub     eax, ecx
        HALF
        mov     [F_TAGX], eax

        cvtsi2ss xmm0, [W]              ; the glow, an ellipse 1.6x wider
        movss   xmm1, xmm0              ; than tall
        mulss   xmm0, [f32_half]
        movss   [F_GX], xmm0
        mulss   xmm1, [f32_0_34]
        movss   [F_GR], xmm1
        cvtsi2ss xmm0, [F_LOGOY]
        cvtsi2ss xmm1, [F_TEXTH]
        mulss   xmm1, [f32_0_55]
        addss   xmm0, xmm1
        movss   [F_GY], xmm0
        mov     edi, [BUF1]             ; dx2[x]: per-column squared distance
        xor     ecx, ecx
.dx2:   cvtsi2ss xmm0, ecx
        subss   xmm0, [F_GX]
        divss   xmm0, [F_GR]
        mulss   xmm0, [f32_1_6]
        mulss   xmm0, xmm0
        movss   [edi+ecx*4], xmm0
        inc     ecx
        cmp     ecx, [W]
        jl      .dx2
        movss   xmm0, [F_GR]
        cvttss2si edx, xmm0             ; span_y
        divss   xmm0, [f32_1_6]
        cvttss2si ecx, xmm0             ; span_x
        cvttss2si eax, [F_GX]
        mov     ebx, eax
        sub     eax, ecx
        mov     [F_BX0], eax
        add     ebx, ecx
        mov     [F_BX1], ebx
        cvttss2si eax, [F_GY]
        mov     ebx, eax
        sub     eax, edx
        mov     [F_BY0], eax
        add     ebx, edx
        mov     [F_BY1], ebx
        ret

; ---------------------------------------------------------------------------
; the 5x7 font, block by block
; ---------------------------------------------------------------------------

; glyph_blocks: walk the 35 dots of glyph [G_PTR] at (G_X, G_Y + row*G_DIR),
; clip each lit dot's scale x scale block to the frame, and call [T_FN] on
; it with the span in B_X0..B_X1, B_Y0..B_Y1. The handler may clobber any
; register, so the walk keeps its counters in memory.
glyph_blocks:
        mov     dword [G_ROW], 0
.row:   mov     esi, [G_PTR]
        add     esi, [G_ROW]
        movzx   eax, byte [esi]
        mov     [G_BITS], eax
        mov     dword [G_COL], 0
.col:   test    dword [G_BITS], 0x10    ; bit 4 is the leftmost dot
        jz      .next
        mov     eax, [G_COL]
        imul    eax, [X_SCALE]
        add     eax, [G_X]              ; px
        mov     edx, [G_ROW]
        imul    edx, [G_DIR]
        add     edx, [G_Y]              ; py
        mov     ecx, eax
        add     ecx, [X_SCALE]
        cmp     ecx, [W]
        cmovg   ecx, [W]
        mov     [B_X1], ecx
        test    eax, eax
        cmovs   eax, [zero]
        mov     [B_X0], eax
        mov     ecx, edx
        add     ecx, [X_SCALE]
        cmp     ecx, [H]
        cmovg   ecx, [H]
        mov     [B_Y1], ecx
        test    edx, edx
        cmovs   edx, [zero]
        mov     [B_Y0], edx
        cmp     eax, [B_X1]
        jge     .next
        cmp     edx, [B_Y1]
        jge     .next
        call    [T_FN]
.next:  shl     dword [G_BITS], 1
        inc     dword [G_COL]
        cmp     dword [G_COL], 5
        jl      .col
        inc     dword [G_ROW]
        cmp     dword [G_ROW], 7
        jl      .row
        ret

; text: draw T_LEN characters of [T_STR] at (T_X, T_Y), each letter moved
; by its offset if T_OFFP is set, mirrored if T_REFL is
text:
        mov     dword [T_I], 0
.char:  mov     esi, [T_STR]
        add     esi, [T_I]
        movzx   eax, byte [esi]
        sub     eax, 32
        lea     eax, [font+eax*8]
        mov     [G_PTR], eax
        mov     eax, [T_I]              ; gx = x + i*6*scale
        imul    eax, eax, 6
        imul    eax, [X_SCALE]
        add     eax, [T_X]
        mov     [G_X], eax
        xor     edx, edx                ; dy = offs[i], or 0
        mov     esi, [T_OFFP]
        test    esi, esi
        jz      .noofs
        mov     ecx, [T_I]
        mov     edx, [esi+ecx*4]
.noofs: mov     eax, [X_SCALE]
        cmp     dword [T_REFL], 0
        jne     .mirror
        mov     [G_DIR], eax            ; rows go down from y + dy
        add     edx, [T_Y]
        mov     [G_Y], edx
        jmp     .walk
.mirror:
        neg     eax                     ; rows go up from y + 6*scale - dy
        mov     [G_DIR], eax
        imul    eax, eax, -6
        add     eax, [T_Y]
        sub     eax, edx
        mov     [G_Y], eax
.walk:  call    glyph_blocks
        inc     dword [T_I]
        mov     eax, [T_I]
        cmp     eax, [T_LEN]
        jl      .char
        ret

; draw_text (esi = string, ecx = length, eax = x, edx = y, ebx = scale,
; edi = colour): the plain solid text
draw_text:
        mov     [T_STR], esi
        mov     [T_LEN], ecx
        mov     [T_X], eax
        mov     [T_Y], edx
        mov     [X_SCALE], ebx
        mov     [T_C], edi
        mov     dword [T_FN], fill_solid
        mov     dword [T_REFL], 0
        mov     dword [T_OFFP], 0
        jmp     text

; ROWPTR: edi = &pix[ebp*w + B_X0], ecx = B_X1 - B_X0
%macro ROWPTR 0
        mov     edi, ebp
        imul    edi, [W]
        add     edi, [B_X0]
        shl     edi, 2
        add     edi, [FB]
        mov     ecx, [B_X1]
        sub     ecx, [B_X0]
%endmacro

fill_solid:
        mov     ebp, [B_Y0]
.row:   ROWPTR
        mov     eax, [T_C]
        rep stosd
        inc     ebp
        cmp     ebp, [B_Y1]
        jl      .row
        ret

; lerp_rgb ([L_A], [L_B], xmm0 = u) -> eax: per channel a + (b - a)*u, f32
%macro LERPC 1
        movzx   eax, byte [L_A+%1]
        cvtsi2ss xmm1, eax
        movzx   eax, byte [L_B+%1]
        cvtsi2ss xmm2, eax
        subss   xmm2, xmm1
        mulss   xmm2, xmm0
        addss   xmm1, xmm2
        cvttss2si eax, xmm1
        mov     [L_OUT+%1], al
%endmacro
lerp_rgb:
        LERPC   0
        LERPC   1
        LERPC   2
        mov     byte [L_OUT+3], 0xFF
        mov     eax, [L_OUT]
        ret

; fill_gradient: each row of the block takes the three-stop gradient at its
; height in the text, and every fourth row is a darker scanline
fill_gradient:
        mov     ebp, [B_Y0]
.row:   mov     eax, ebp
        sub     eax, [T_Y]
        cvtsi2ss xmm0, eax
        mov     eax, [X_SCALE]
        imul    eax, eax, 7
        cvtsi2ss xmm1, eax
        divss   xmm0, xmm1              ; f = (yy - y)/total_h, clamped
        CLAMPF  xmm0
        comiss  xmm0, [f32_half]
        jae     .lower
        mov     dword [L_A], TOP_C      ; top half: cream to rose
        mov     dword [L_B], MID_C
        addss   xmm0, xmm0
        jmp     .lerp
.lower: mov     dword [L_A], MID_C      ; bottom half: rose to violet
        mov     dword [L_B], BOT_C
        subss   xmm0, [f32_half]
        addss   xmm0, xmm0
.lerp:  call    lerp_rgb
        test    ebp, 3                  ; scanline: each channel * 3/4
        jnz     .fill
        mov     ecx, 2
.dim:   movzx   eax, byte [L_OUT+ecx]
        imul    eax, eax, 3
        shr     eax, 2
        mov     [L_OUT+ecx], al
        dec     ecx
        jns     .dim
        mov     eax, [L_OUT]
.fill:  mov     ebx, eax
        ROWPTR
        mov     eax, ebx
        rep stosd
        inc     ebp
        cmp     ebp, [B_Y1]
        jl      .row
        ret

; ADDI k: byte k of [edi] += byte k of [A_C] * [A_I] / 255, saturated
%macro ADDI 1
        movzx   eax, byte [A_C+%1]
        imul    eax, [A_I]
        xor     edx, edx
        div     dword [c255]
        movzx   edx, byte [edi+%1]
        add     eax, edx
        cmp     eax, 255
        cmovg   eax, [c255]
        mov     [edi+%1], al
%endmacro

; additive (edi = pixel address, [A_C], [A_I]): canvas_additive
additive:
        cmp     dword [A_I], 0
        je      .done
        ADDI    0
        ADDI    1
        ADDI    2
        mov     byte [edi+3], 0xFF
.done:  ret

; fill_reflect: the mirrored glyph, added to the floor with a light that
; fades as (1 - d)^2 over the reflection's depth
fill_reflect:
        mov     ebp, [B_Y0]
.row:   mov     eax, ebp
        sub     eax, [T_Y]
        cvtsi2ss xmm0, eax
        cvtsi2ss xmm1, [F_DEPTH]
        divss   xmm0, xmm1              ; d = (yy - y)/depth
        comiss  xmm0, [f32_one]
        ja      .next
        movss   xmm1, [f32_one]
        subss   xmm1, xmm0
        mulss   xmm1, xmm1              ; a = (1 - d)^2
        mulss   xmm1, [f32_125]
        cvttss2si eax, xmm1             ; intensity = 125*a
        test    eax, eax
        jz      .next
        mov     [A_I], eax
        mov     dword [L_A], TOP_C
        mov     dword [L_B], BOT_C
        call    lerp_rgb
        mov     [A_C], eax
        ROWPTR
.px:    push    ecx
        call    additive
        pop     ecx
        add     edi, 4
        dec     ecx
        jnz     .px
.next:  inc     ebp
        cmp     ebp, [B_Y1]
        jl      .row
        ret

; hline (eax = x, edx = y, ecx = length, ebx = colour), clipped
hline:
        cmp     edx, 0
        jl      .done
        cmp     edx, [H]
        jge     .done
        add     ecx, eax                ; x1 = min(x + len, w)
        cmp     ecx, [W]
        cmovg   ecx, [W]
        test    eax, eax                ; x0 = max(x, 0)
        cmovs   eax, [zero]
        sub     ecx, eax
        jle     .done
        imul    edx, [W]
        add     edx, eax
        shl     edx, 2
        add     edx, [FB]
        mov     edi, edx
        mov     eax, ebx
        rep stosd
.done:  ret

; ---------------------------------------------------------------------------
; the backdrop
; ---------------------------------------------------------------------------

; CHANF dst, a, k: dst = (a + k*u)*vig as f32, then a byte at [edi+n]
%macro CHANF 4
        movss   xmm0, xmm6
        mulss   xmm0, [%2]
        %3
        addss   xmm0, [%1]
        mulss   xmm0, xmm7
        cvtss2sd xmm3, xmm0
        call    to_byte
        mov     [L_OUT+%4], cl
%endmacro

; GLOWC k, f: channel k of [edi] += int(g*f), g in xmm1, saturated
%macro GLOWC 2
        movss   xmm2, xmm1
        mulss   xmm2, [%2]
        cvttss2si eax, xmm2
        movzx   edx, byte [edi+%1]
        add     eax, edx
        cmp     eax, 255
        cmovg   eax, [c255]
        mov     [edi+%1], al
%endmacro

; FLOORC k, f: channel k of [edi] = min(p + f*glow, 255) in f32, glow in xmm1
%macro FLOORC 2
        movzx   eax, byte [edi+%1]
        cvtsi2ss xmm2, eax
        movss   xmm3, xmm1
        mulss   xmm3, [%2]
        addss   xmm2, xmm3
        minss   xmm2, [f32_255]
        cvttss2si eax, xmm2
        mov     [edi+%1], al
%endmacro

finale_backdrop:
        cvtsi2ss xmm5, [H]              ; pass 1: a vertical ramp, one
        movss   xmm4, [f32_one]         ; colour per row
        divss   xmm4, xmm5              ; inv_h
        mulss   xmm5, [f32_half]        ; cy
        mov     edi, [FB]
        xor     esi, esi
.ramp:  cvtsi2ss xmm6, esi
        movss   xmm7, xmm6
        mulss   xmm6, xmm4              ; u = y*inv_h
        subss   xmm7, xmm5
        divss   xmm7, xmm5              ; ny = (y - cy)/cy
        movss   xmm0, xmm7
        mulss   xmm0, [f32_0_32]
        mulss   xmm0, xmm7
        movss   xmm7, [f32_one]
        subss   xmm7, xmm0              ; vig = 1 - 0.32*ny*ny, at least 0.45
        comiss  xmm7, [f32_0_45]
        jae     .vig
        movss   xmm7, [f32_0_45]
.vig:   CHANF   f32_0_02, f32_0_09, {mulss xmm0, xmm6}, 0  ; (0.02 + 0.09*u*u)*vig
        CHANF   f32_0_01, f32_0_02, {}, 1                  ; (0.01 + 0.02*u)*vig
        CHANF   f32_0_06, f32_0_14x, {}, 2                 ; (0.06 + 0.14*u)*vig
        mov     byte [L_OUT+3], 0xFF
        mov     eax, [L_OUT]
        mov     ecx, [W]
        rep stosd
        inc     esi
        cmp     esi, [H]
        jl      .ramp

        movsd   xmm0, [BEAT]            ; pass 2: the pool of light, pulsing
        mulsd   xmm0, [f64_2_2]
        call    sin64
        cvtsd2ss xmm0, xmm0
        mulss   xmm0, [f32_0_12]
        addss   xmm0, [f32_0_88]
        movss   [F_PULSE], xmm0
        mov     esi, [F_BY0]
        test    esi, esi
        cmovs   esi, [zero]
.grow:  cmp     esi, [F_BY1]
        jge     .stars
        cmp     esi, [H]
        jge     .stars
        cvtsi2ss xmm7, esi
        subss   xmm7, [F_GY]
        divss   xmm7, [F_GR]
        mulss   xmm7, xmm7              ; dy2
        comiss  xmm7, [f32_one]
        jae     .gnext
        mov     ebx, [F_BX0]
        test    ebx, ebx
        cmovs   ebx, [zero]
.gpx:   cmp     ebx, [F_BX1]
        jge     .gnext
        cmp     ebx, [W]
        jge     .gnext
        mov     eax, [BUF1]
        movss   xmm0, [eax+ebx*4]
        addss   xmm0, xmm7              ; d2 = dx2[x] + dy2
        comiss  xmm0, [f32_one]
        jae     .gskip
        movss   xmm1, [f32_one]
        subss   xmm1, xmm0              ; g = 1 - d2
        movss   xmm0, xmm1
        mulss   xmm0, [F_PULSE]
        mulss   xmm1, xmm0              ; g *= g*pulse
        mov     edi, esi
        imul    edi, [W]
        add     edi, ebx
        shl     edi, 2
        add     edi, [FB]
        GLOWC   0, f32_120
        GLOWC   1, f32_22
        GLOWC   2, f32_100
        mov     byte [edi+3], 0xFF
.gskip: inc     ebx
        jmp     .gpx
.gnext: inc     esi
        jmp     .grow

.stars: mov     dword [F_I], 0          ; stars, twinkling slowly
        mov     ebx, stars
.star:  cvtsi2ss xmm0, [W]
        mulss   xmm0, [ebx]
        cvttss2si esi, xmm0             ; sx
        cvtsi2ss xmm0, [H]
        mulss   xmm0, [ebx+4]
        cvttss2si edi, xmm0             ; sy
        cmp     edi, 0
        jl      .snext
        cmp     edi, [H]
        jge     .snext
        cmp     esi, 0
        jl      .snext
        cmp     esi, [W]
        jge     .snext
        cvtsi2sd xmm1, [F_I]            ; tw = 0.55 + 0.45*sin(t*1.7 + i*0.7)
        mulsd   xmm1, [f64_0_7]
        movsd   xmm0, [BEAT]
        mulsd   xmm0, [f64_1_7]
        addsd   xmm0, xmm1
        call    sin64
        cvtsd2ss xmm0, xmm0
        mulss   xmm0, [f32_0_45]
        addss   xmm0, [f32_0_55]
        movss   xmm1, [ebx+8]
        mulss   xmm1, [f32_70]
        mulss   xmm1, xmm0
        cvttss2si eax, xmm1             ; intensity = 70*b*tw
        mov     [A_I], eax
        mov     dword [A_C], 0xFF40306A
        imul    edi, [W]
        add     edi, esi
        shl     edi, 2
        add     edi, [FB]
        call    additive
.snext: add     ebx, 12
        inc     dword [F_I]
        cmp     dword [F_I], 260
        jl      .star

        mov     esi, [F_FLOORY]         ; the polished floor line the
        cmp     esi, 0                  ; reflection lands on
        jl      .done
        cmp     esi, [H]
        jge     .done
        imul    esi, [W]
        shl     esi, 2
        add     esi, [FB]
        cvtsi2ss xmm6, [W]
        movss   xmm5, xmm6
        mulss   xmm6, [f32_half]        ; cx
        mulss   xmm5, [f32_0_52]        ; w*0.52
        xor     ebx, ebx
.fl:    cvtsi2ss xmm0, ebx
        subss   xmm0, xmm6
        andps   xmm0, [abs32]
        divss   xmm0, xmm5
        movss   xmm1, [f32_one]
        subss   xmm1, xmm0              ; fade = 1 - |x - cx|/(w*0.52)
        comiss  xmm1, [f32_zero]
        jbe     .flnext
        mulss   xmm1, xmm1
        mulss   xmm1, [f32_0_9]         ; glow = fade*fade*0.9
        lea     edi, [esi+ebx*4]
        FLOORC  0, f32_210
        FLOORC  1, f32_110
        FLOORC  2, f32_230
        mov     byte [edi+3], 0xFF
.flnext:
        inc     ebx
        cmp     ebx, [W]
        jl      .fl
.done:  ret

; ---------------------------------------------------------------------------
; the card
; ---------------------------------------------------------------------------

F_DEPTH equ F_REFLH

finale_render:
        call    finale_backdrop
        mov     dword [F_I], 0          ; the letters bounce off the floor:
.bounce:                                ; (sin(t*2.4 + i*0.75) - 1)*scale/6
        cvtsi2sd xmm1, [F_I]
        mulsd   xmm1, [f64_0_75]
        movsd   xmm0, [BEAT]
        mulsd   xmm0, [f64_2_4]
        addsd   xmm0, xmm1
        call    sin64
        subsd   xmm0, [f64_one]
        cvtsi2sd xmm1, [F_LOGOS]
        mulsd   xmm0, xmm1
        divsd   xmm0, [f64_6]
        cvttsd2si eax, xmm0
        mov     ecx, [F_I]
        mov     [F_OFFS+ecx*4], eax
        inc     ecx
        mov     [F_I], ecx
        cmp     ecx, LANG_LEN
        jl      .bounce

; @excerpt FINALE
        ; the reflection first, so the wordmark sits on its own light
        mov     dword [T_STR], lang
        mov     dword [T_LEN], LANG_LEN
        mov     eax, [F_LOGOX]
        mov     [T_X], eax
        mov     eax, [F_FLOORY]
        mov     [T_Y], eax
        mov     eax, [F_LOGOS]
        mov     [X_SCALE], eax
        mov     dword [T_FN], fill_reflect
        mov     dword [T_REFL], 1       ; rows mirrored about the floor
        mov     dword [T_OFFP], F_OFFS
        call    text
        ; a one-pixel dark edge: each letter four times, nudged by one
        mov     dword [T_I], 0
        mov     dword [F_I], 0
.letter:
        mov     dword [F_J], 0
.nudge: mov     esi, [F_J]
        mov     eax, [F_I]              ; gx = logo_x + i*6*scale + ddx
        imul    eax, eax, 6
        imul    eax, [F_LOGOS]
        add     eax, [F_LOGOX]
        add     eax, [nudge_x+esi*4]
        mov     ecx, [F_I]
        mov     edx, [F_OFFS+ecx*4]     ; y + dy + ddy
        add     edx, [F_LOGOY]
        add     edx, [nudge_y+esi*4]
        lea     esi, [lang+ecx]
        mov     ecx, 1
        mov     ebx, [F_LOGOS]
        mov     edi, 0xFF200A18
        call    draw_text
        inc     dword [F_J]
        cmp     dword [F_J], 4
        jl      .nudge
        inc     dword [F_I]
        cmp     dword [F_I], LANG_LEN
        jl      .letter
        ; the wordmark: cream, rose, violet, with scanlines
        mov     dword [T_STR], lang
        mov     dword [T_LEN], LANG_LEN
        mov     eax, [F_LOGOX]
        mov     [T_X], eax
        mov     eax, [F_LOGOY]
        mov     [T_Y], eax
        mov     eax, [F_LOGOS]
        mov     [X_SCALE], eax
        mov     dword [T_FN], fill_gradient
        mov     dword [T_REFL], 0
        mov     dword [T_OFFP], F_OFFS
        call    text
; @end

        WIDTH   sub_len, [F_SUBS]       ; the subtitle, a rule either side
        mov     esi, eax                ; sub_w
        SDIV    k_3
        mov     ebp, eax                ; rule = sub_w/3
        mov     eax, [F_SUBS]
        imul    eax, eax, 7
        HALF
        add     eax, [F_SUBY]
        mov     [F_J], eax              ; ly
        mov     eax, [F_SUBX]
        sub     eax, ebp
        sub     eax, 14
        mov     edx, [F_J]
        mov     ecx, ebp
        mov     ebx, 0xFF9050A0
        push    esi
        call    hline
        pop     esi
        mov     eax, [F_SUBX]
        add     eax, esi
        add     eax, 14
        mov     edx, [F_J]
        mov     ecx, ebp
        mov     ebx, 0xFF9050A0
        call    hline
        mov     esi, sub_s
        mov     ecx, sub_len
        mov     eax, [F_SUBX]
        mov     edx, [F_SUBY]
        mov     ebx, [F_SUBS]
        mov     edi, 0xFFF0E0FF
        call    draw_text

        mov     dword [F_I], 0          ; the closing numbers, centred
.line:  mov     ecx, [F_I]
        mov     esi, [lines+ecx*8]
        mov     ecx, [lines+ecx*8+4]
        WIDTH   ecx, [F_STATS]
        mov     edx, [W]
        sub     edx, eax
        mov     eax, edx
        HALF
        mov     edx, [F_I]
        imul    edx, [F_GAPS]
        add     edx, [F_STATSY]
        mov     ebx, [F_STATS]
        mov     edi, 0xFFC0B0E0
        call    draw_text
        inc     dword [F_I]
        cmp     dword [F_I], 3
        jl      .line

        mov     esi, tag_s              ; the punchline
        mov     ecx, tag_len
        mov     eax, [F_TAGX]
        mov     edx, [F_TAGY]
        mov     ebx, [F_TAGS]
        mov     edi, 0xFFB0E0FF
        jmp     draw_text

lang:    db LANG
sub_s:   db 'EVERY PIXEL IS ', LANG
sub_len  equ $ - sub_s
tag_s:   db 'ONE THREAD - NO GPU - NO SHADER'
tag_len  equ $ - tag_s
line0:   db '0 GPU SHADERS'
line1:   db '0 EXTERNAL MODULES'
line2:   db '0 ASSETS ON DISK'
line3:
align 4
lines:   dd line0, line1 - line0, line1, line2 - line1, line2, line3 - line2
nudge_x: dd -1, 1, 0, 0
nudge_y: dd 0, 0, -1, 1
k_2:     dd 2
k_3:     dd 3
k_20:    dd 20
k_21:    dd 21
k_40:    dd 40
k_48:    dd 48
k_300:   dd 300
k_440:   dd 440
f32_0_15:  dd 0.15
f32_0_90:  dd 0.90
f32_0_34:  dd 0.34
f32_0_14x: dd 0.14
f32_0_88:  dd 0.88
f32_22:    dd 22.0
f32_100:   dd 100.0
f32_70:    dd 70.0
f32_0_9:   dd 0.9
f32_210:   dd 210.0
f32_110:   dd 110.0
f32_230:   dd 230.0
f32_125:   dd 125.0
align 8
f64_2_2:   dq 2.2
f64_1_7:   dq 1.7
f64_0_75:  dq 0.75
f64_2_4:   dq 2.4
