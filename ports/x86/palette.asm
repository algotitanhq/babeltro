; palette: the 256-colour ramps, built once from a few colour stops
;
; A stop is four f64: position in [0,1], then red, green, blue. Between two
; stops the colour follows a smoothstep, so the gradients do not band.

build_palettes:
        mov     edi, sunset
        mov     esi, sunset_stops
        mov     ecx, 7
        call    build_ramp
        mov     edi, ember
        mov     esi, ember_stops
        mov     ecx, 6
        jmp     build_ramp              ; tail call

; one channel of entry ebx: a.c + (b.c - a.c)*u, to a byte, stored at
; byte %2 of the pixel (R, G, B, A in memory: little-endian 0xAABBGGRR)
%macro channel 2
        movsd   xmm3, [edx+%1]
        subsd   xmm3, [eax+%1]
        mulsd   xmm3, xmm1
        addsd   xmm3, [eax+%1]
        call    to_byte
        mov     [edi+ebx*4+%2], cl
%endmacro

; build_ramp(edi = 256 pixels, esi = stops, ecx = how many)
build_ramp:
        mov     [SCRAT], ecx
        xor     ebx, ebx
.each:
        cvtsi2sd xmm0, ebx
        divsd   xmm0, [f64_255]         ; t = i/255
        ; find the segment holding t; if none does, first and last stop
        mov     eax, esi
        mov     edx, [SCRAT]
        dec     edx
        shl     edx, 5                  ; 32 bytes per stop
        add     edx, esi
        mov     ecx, [SCRAT]
        dec     ecx
        mov     ebp, esi
.seek:
        comisd  xmm0, [ebp]             ; t >= stops[k].pos ?
        jb      .next
        comisd  xmm0, [ebp+32]          ; t <= stops[k+1].pos ?
        ja      .next
        mov     eax, ebp
        lea     edx, [ebp+32]
        jmp     .found
.next:  add     ebp, 32
        dec     ecx
        jnz     .seek
.found:
        ; u = (t - a.pos) / (b.pos - a.pos), or 0 for an empty segment
        xorpd   xmm1, xmm1
        movsd   xmm2, [edx]
        comisd  xmm2, [eax]
        jbe     .clamp
        movsd   xmm1, xmm0
        subsd   xmm1, [eax]
        subsd   xmm2, [eax]
        divsd   xmm1, xmm2
.clamp: maxsd   xmm1, [f64_zero]        ; clamp to [0,1]
        minsd   xmm1, [f64_one]
        movsd   xmm2, xmm1              ; smoothstep: u*u*(3 - 2*u)
        mulsd   xmm2, xmm1
        addsd   xmm1, xmm1
        movsd   xmm3, [f64_three]
        subsd   xmm3, xmm1
        mulsd   xmm2, xmm3
        movsd   xmm1, xmm2
        channel 8, 0
        channel 16, 1
        channel 24, 2
        mov     byte [edi+ebx*4+3], 0xFF ; alpha, always opaque
        inc     ebx
        cmp     ebx, 256
        jl      .each
        ret

; to_byte (xmm3 = v in [0,1]) -> ecx = 0..255, rounded, clamped
to_byte:
        xor     ecx, ecx
        comisd  xmm3, [f64_zero]
        jbe     .done
        mov     ecx, 255
        comisd  xmm3, [f64_one]
        jae     .done
        mulsd   xmm3, [f64_255]
        addsd   xmm3, [f64_half]
        cvttsd2si ecx, xmm3
.done:  ret

align 8
f64_zero:  dq 0.0
f64_half:  dq 0.5
f64_three: dq 3.0
f64_255:   dq 255.0
sunset_stops:
        dq 0.00, 0.02, 0.00, 0.06
        dq 0.18, 0.25, 0.02, 0.38
        dq 0.38, 0.72, 0.05, 0.45
        dq 0.56, 0.98, 0.25, 0.22
        dq 0.74, 1.00, 0.62, 0.15
        dq 0.88, 1.00, 0.93, 0.55
        dq 1.00, 1.00, 1.00, 0.96
ember_stops:
        dq 0.00, 0.00, 0.00, 0.00
        dq 0.20, 0.25, 0.00, 0.00
        dq 0.45, 0.80, 0.10, 0.00
        dq 0.68, 1.00, 0.45, 0.00
        dq 0.85, 1.00, 0.80, 0.15
        dq 1.00, 1.00, 1.00, 0.85
