; fire: the Doom fire algorithm. A heat buffer is seeded at the bottom row
; and diffused upward with a little random sideways drift. Integer only,
; one byte per pixel: the scene this instruction set was born for.

; XORSHIFT reg: xorshift32 in place, the same sequence in every language
; (clobbers eax)
%macro XORSHIFT 1
        mov     eax, %1
        shl     eax, 13
        xor     %1, eax
        mov     eax, %1
        shr     eax, 17
        xor     %1, eax
        mov     eax, %1
        shl     eax, 5
        xor     %1, eax
%endmacro

; PALROW: one row of heat bytes [edi] to colours [ebp] (clobbers eax, ecx)
%macro PALROW 0
        xor     ecx, ecx
%%px:   movzx   eax, byte [edi+ecx]
        mov     eax, [ember+eax*4]
        mov     [ebp+ecx*4], eax
        inc     ecx
        cmp     ecx, [W]
        jl      %%px
%endmacro

F_ROWS  equ SCRAT

fire_start:
        mov     dword [RNG], 0x9E3779B9
        mov     edi, [HEAT]
        mov     ecx, [N]
        xor     eax, eax
        rep stosb                       ; the whole buffer cold, one instruction
        ret

; fire_render(eax = frame number)
fire_render:
        ; seed the hottest row: a slow horizontal wave gives the fire its
        ; uneven base, the random term keeps the tongues from looking periodic
        cvtsi2ss xmm7, eax
        mulss   xmm7, [f32_0_05]        ; t = frame * 0.05
        movss   xmm6, xmm7
        mulss   xmm6, [f32_1_7]         ; t*1.7
        cvtsi2ss xmm5, [W]
        mov     ebx, [RNG]              ; the generator lives in ebx all frame
        mov     edi, [HEAT]
        add     edi, [N]
        sub     edi, [W]                ; the bottom row
        xor     ecx, ecx
.seed:  cvtsi2ss xmm0, ecx
        divss   xmm0, xmm5              ; fx = x/w
        movss   xmm1, xmm0
        mulss   xmm0, [f32_11]          ; 0.5 + 0.5*sin(fx*11 + t)*0.6
        addss   xmm0, xmm7
        SIN     xmm0
        mulss   xmm0, [f32_half]
        mulss   xmm0, [f32_0_6]
        addss   xmm0, [f32_half]
        mulss   xmm1, [f32_23]          ;  + 0.5*sin(fx*23 - t*1.7)*0.4
        subss   xmm1, xmm6
        SIN     xmm1
        mulss   xmm1, [f32_half]
        mulss   xmm1, [f32_0_4]
        addss   xmm0, xmm1
        mulss   xmm0, [f32_90]          ; 150 + wave*90 + (rand & 31) - 16
        addss   xmm0, [f32_150]
        XORSHIFT ebx
        mov     eax, ebx
        and     eax, 31
        cvtsi2ss xmm1, eax
        addss   xmm0, xmm1
        subss   xmm0, [f32_16]
        minss   xmm0, [f32_255]         ; clamp to 90..255
        maxss   xmm0, [f32_90]
        cvttss2si eax, xmm0
        mov     [edi+ecx], al
        inc     ecx
        cmp     ecx, [W]
        jl      .seed

        mov     ebp, [N]                ; the bottom row's colours
        sub     ebp, [W]
        shl     ebp, 2
        add     ebp, [FB]
        PALROW

        ; diffuse upward: every destination pixel takes one value from the
        ; row below, offset sideways by a random -1/0/+1. Gather, not
        ; scatter, so each pixel is written exactly once.
        mov     esi, edi
        mov     eax, [H]
        dec     eax
        mov     [F_ROWS], eax
; @excerpt FIRE
        ; esi = source row (below), edi = destination row, ebx = rng
.row:   mov     edi, esi
        sub     edi, [W]
        xor     ecx, ecx                ; x
.px:    movzx   eax, byte [esi+ecx]
        test    eax, eax
        jz      .store                  ; cold below: no random draw, stay cold
        XORSHIFT ebx                    ; r = next()
        mov     eax, ebx
        xor     edx, edx
        div     dword [three]           ; edx = r % 3: the drift, 0 1 2
        lea     edx, [ecx+edx-1]        ; sx = x - 1, x or x + 1
        test    edx, edx
        cmovs   edx, [zero]             ; clamp to the left edge...
        cmp     edx, [W]
        cmovge  edx, [W1]               ; ...and to the right one
        movzx   eax, byte [esi+edx]     ; v = src[sx]
        mov     edx, ebx
        shr     edx, 16
        and     edx, 1                  ; decay = r >> 16 & 1
        sub     eax, edx
        cmovs   eax, [zero]             ; v > decay ? v - decay : 0
.store: mov     [edi+ecx], al
        inc     ecx
        cmp     ecx, [W]
        jl      .px
        mov     eax, [W]                ; the row is done: colour it now,
        shl     eax, 2                  ; while it is still in the cache
        sub     ebp, eax
        PALROW
        mov     esi, edi                ; one row up
        dec     dword [F_ROWS]
        jnz     .row
; @end
        mov     [RNG], ebx
        ret

align 4
f32_0_05:  dd 0.05
f32_1_7:   dd 1.7
f32_11:    dd 11.0
f32_23:    dd 23.0
f32_0_6:   dd 0.6
f32_0_4:   dd 0.4
f32_90:    dd 90.0
f32_150:   dd 150.0
f32_16:    dd 16.0
f32_255:   dd 255.0
