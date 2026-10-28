; fmath: the sine table, with no maths library underneath
;
; There is no libm on this machine, and the x87's fsin is out (80-bit, and
; its argument reduction is famously sloppy near pi). So sin is written
; out: a Cody-Waite range reduction to [-pi/4, pi/4], then a Taylor series
; in f64, the same recipe as the hand-written wasm port. Rounded to f32,
; all 8193 entries equal Go's fmath.SinTab bit for bit.

; reduce (xmm0 = x) -> xmm0 = r, eax = quadrant k, with x = k*(pi/2) + r.
; cvtsd2si rounds to nearest (the MXCSR default), which is f64.nearest.
; pi/2 is split in two: PIO2_HI has 33 significant bits, so k*PIO2_HI is
; exact and x - k*PIO2_HI loses nothing; PIO2_LO puts back what it dropped.
reduce:
        movsd   xmm1, xmm0
        mulsd   xmm1, [two_over_pi]
        cvtsd2si eax, xmm1              ; k = nearest(x * 2/pi)
        cvtsi2sd xmm1, eax
        movsd   xmm2, xmm1
        mulsd   xmm1, [pio2_hi]
        subsd   xmm0, xmm1              ; x - k*PIO2_HI
        mulsd   xmm2, [pio2_lo]
        subsd   xmm0, xmm2              ; ... - k*PIO2_LO
        ret

; ksin (xmm0 = r) -> xmm0 = sin r on |r| <= pi/4, by Horner's rule:
; sin r = r + r*z*(-1/3! + z*(1/5! + z*(-1/7! + ...))), z = r*r.
; Every mulsd and addsd rounds once: there is no fused multiply-add here.
ksin:
        movsd   xmm1, xmm0
        mulsd   xmm1, xmm0              ; z
        movsd   xmm2, [sin_c]           ; 1/17!
        mov     ecx, 7                  ; seven more coefficients
        mov     edx, sin_c + 8
.horner:
        mulsd   xmm2, xmm1
        addsd   xmm2, [edx]
        add     edx, 8
        dec     ecx
        jnz     .horner
        mulsd   xmm1, xmm0              ; r*z
        mulsd   xmm1, xmm2
        addsd   xmm0, xmm1
        ret

; kcos (xmm0 = r) -> xmm0 = cos r = 1 + z*(-1/2! + z*(1/4! + ...)).
kcos:
        mulsd   xmm0, xmm0              ; z
        movsd   xmm2, [cos_c]           ; -1/18!
        mov     ecx, 8
        mov     edx, cos_c + 8
.horner:
        mulsd   xmm2, xmm0
        addsd   xmm2, [edx]
        add     edx, 8
        dec     ecx
        jnz     .horner
        mulsd   xmm0, xmm2
        addsd   xmm0, [f64_one]
        ret

; sin64 (xmm0 = x) -> xmm0 = sin x. Odd quadrants swap sin for cos,
; quadrants 2 and 3 flip the sign; k & 3 is right for negative k too.
sin64:
        call    reduce
        push    eax
        test    eax, 1
        jz      .even
        call    kcos
        jmp     .sign
.even:  call    ksin
.sign:  pop     eax
        test    eax, 2
        jz      .done
        xorpd   xmm0, [sign64]          ; flip the sign bit, nothing else
.done:  ret

; build_sintab is Go's fmath.init: a = 2*pi*i/8192 in f64, exactly as Go
; writes it, then sin(a) rounded to f32 by cvtsd2ss.
build_sintab:
        xor     ebx, ebx
.each:
        cvtsi2sd xmm0, ebx
        mulsd   xmm0, [two_pi]
        divsd   xmm0, [f64_8192]
        call    sin64
        cvtsd2ss xmm0, xmm0
        movss   [sintab+ebx*4], xmm0
        inc     ebx
        cmp     ebx, 8192
        jl      .each
        mov     eax, [sintab]           ; a full period wraps exactly
        mov     [sintab+8192*4], eax
        ret

; The lookup every effect inlines, fmath.Sin:
;       mulss     xmm, [inv2pi]         ; radians to table steps
;       cvttss2si eax, xmm              ; truncate toward zero, like Go's int()
;       and       eax, 8191             ; wrap; -3 & 8191 = 8189 as in Go
;       movss     xmm, [sintab+eax*4]
; cvttss2si answers 0x80000000 (the "integer indefinite") to NaN and to
; anything out of range; Go's angles never get there.

align 8
two_over_pi: dq 0.6366197723675814
pio2_hi:     dq 1.5707963267341256
pio2_lo:     dq 6.077100506506192e-11
two_pi:      dq 6.283185307179586
f64_8192:    dq 8192.0
f64_one:     dq 1.0
align 16
sign64:      dq 0x8000000000000000, 0
sin_c:  dq  2.8114572543455206e-15  ;  1/17!
        dq -7.647163731819816e-13   ; -1/15!
        dq  1.6059043836821613e-10  ;  1/13!
        dq -2.505210838544172e-8    ; -1/11!
        dq  2.7557319223985893e-6   ;  1/9!
        dq -1.984126984126984e-4    ; -1/7!
        dq  8.333333333333333e-3    ;  1/5!
        dq -0.16666666666666666     ; -1/3!
cos_c:  dq -1.5619206968586225e-16  ; -1/18!
        dq  4.779477332387385e-14   ;  1/16!
        dq -1.1470745597729725e-11  ; -1/14!
        dq  2.08767569878681e-9     ;  1/12!
        dq -2.755731922398589e-7    ; -1/10!
        dq  2.48015873015873e-5     ;  1/8!
        dq -1.388888888888889e-3    ; -1/6!
        dq  4.1666666666666664e-2   ;  1/4!
        dq -0.5                     ; -1/2!
inv2pi: dd 1303.7972412109375       ; 8192/(2*pi), as f32
