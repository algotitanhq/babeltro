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
.quadrant:
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

; cos64 (xmm0 = x) -> xmm0 = cos x: sin a quarter turn later, the same r
; and the next quadrant
cos64:
        call    reduce
        inc     eax
        jmp     sin64.quadrant

; build_sintab is Go's fmath.init: a = 2*pi*i/8192 in f64, exactly as Go
; writes it, then sin(a) and cos(a) rounded to f32 by cvtsd2ss.
build_sintab:
        xor     ebx, ebx
.each:
        cvtsi2sd xmm0, ebx
        mulsd   xmm0, [two_pi]
        divsd   xmm0, [f64_8192]
        movsd   xmm7, xmm0
        call    sin64
        cvtsd2ss xmm0, xmm0
        movss   [sintab+ebx*4], xmm0
        movsd   xmm0, xmm7
        call    cos64
        cvtsd2ss xmm0, xmm0
        movss   [costab+ebx*4], xmm0
        inc     ebx
        cmp     ebx, 8192
        jl      .each
        mov     eax, [sintab]           ; a full period wraps exactly
        mov     [sintab+8192*4], eax
        mov     eax, [costab]
        mov     [costab+8192*4], eax
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

; ---------------------------------------------------------------------------
; atan2 and exp, f64, also by hand
; ---------------------------------------------------------------------------

FM_Y    equ SCRAT+240           ; atan2 keeps its arguments here, to read
FM_X    equ SCRAT+248           ; their sign bits as integers

; build_atan stores the Taylor coefficients of atan, (-1)^k / (2k+1) for
; k = 0..20, each a single correctly rounded division
build_atan:
        xor     ecx, ecx
.k:     lea     eax, [ecx+ecx+1]
        cvtsi2sd xmm1, eax
        movsd   xmm0, [f64_one]
        test    ecx, 1
        jz      .pos
        xorpd   xmm0, [sign64]
.pos:   divsd   xmm0, xmm1
        movsd   [atan_c+ecx*8], xmm0
        inc     ecx
        cmp     ecx, 21
        jl      .k
        ret

; atan01 (xmm0 = t in [0,1]) -> xmm0 = atan t. Above tan(pi/8),
; atan t = pi/4 + atan((t-1)/(t+1)) brings the argument under 0.4143, where
; 21 terms leave an error below 1e-18.
atan01:
        xorpd   xmm3, xmm3              ; base
        comisd  xmm0, [tan_pi8]
        jbe     .series
        movsd   xmm3, [pi_4]
        movsd   xmm1, xmm0
        subsd   xmm1, [f64_one]
        addsd   xmm0, [f64_one]
        divsd   xmm1, xmm0
        movsd   xmm0, xmm1
.series:
        movsd   xmm1, xmm0
        mulsd   xmm1, xmm0              ; z^2
        xorpd   xmm2, xmm2
        mov     ecx, 20
.term:  mulsd   xmm2, xmm1              ; acc = acc*z^2 + c[k], k = 20..0
        addsd   xmm2, [atan_c+ecx*8]
        dec     ecx
        jns     .term
        mulsd   xmm0, xmm2
        addsd   xmm0, xmm3
        ret

; atan2 (xmm0 = y, xmm1 = x) -> xmm0. Fold the plane onto the first octant,
; unfold the answer: pi/2 - a above the diagonal, pi - a for x < 0 (the sign
; bit, so -0 counts), and the sign of y.
atan2:
        movsd   [FM_Y], xmm0
        movsd   [FM_X], xmm1
        andpd   xmm0, [abs64]           ; |y|
        andpd   xmm1, [abs64]           ; |x|
        comisd  xmm0, xmm1
        ja      .steep
        xorpd   xmm2, xmm2
        comisd  xmm1, xmm2
        jbe     .origin                 ; atan2(0, 0) is 0
        divsd   xmm0, xmm1
        call    atan01
        jmp     .unfold
.origin:
        xorpd   xmm0, xmm0
        jmp     .unfold
.steep: divsd   xmm1, xmm0
        movsd   xmm0, xmm1
        call    atan01
        movsd   xmm1, [pi_2]
        subsd   xmm1, xmm0
        movsd   xmm0, xmm1
.unfold:
        cmp     dword [FM_X+4], 0       ; the high dword holds the sign bit
        jge     .right
        movsd   xmm1, [pi]
        subsd   xmm1, xmm0
        movsd   xmm0, xmm1
.right: cmp     dword [FM_Y+4], 0
        jge     .done
        xorpd   xmm0, [sign64]
.done:  ret

; atan2_turns (xmm0 = y, xmm1 = x, f32) -> xmm0 = atan2 as a fraction of a
; turn, in [0,1), f32: fmath.Atan2
atan2_turns:
        cvtss2sd xmm0, xmm0
        cvtss2sd xmm1, xmm1
        call    atan2
        cvtsd2ss xmm0, xmm0
        divss   xmm0, [f32_2pi]
        addss   xmm0, [f32_half]
        ret

; exp64 (xmm0 = x) -> xmm0 = e^x = 2^k * e^r, k the nearest integer to
; x/ln2, |r| <= ln2/2 (ln2 split in two, as pi/2 was). e^r is
; 1 + (r + r^2*(1/2! + r*(1/3! + ...))): the small part first, the 1 last.
; 2^k takes no arithmetic: it is the f64 whose exponent field is k + 1023.
exp64:
        movsd   xmm1, xmm0
        mulsd   xmm1, [inv_ln2]
        cvtsd2si eax, xmm1              ; k
        cvtsi2sd xmm1, eax
        movsd   xmm2, xmm1
        mulsd   xmm2, [ln2_hi]
        subsd   xmm0, xmm2
        mulsd   xmm1, [ln2_lo]
        subsd   xmm0, xmm1              ; r
        movsd   xmm2, [exp_c]           ; 1/14!
        mov     ecx, 12
        mov     edx, exp_c + 8
.horner:
        mulsd   xmm2, xmm0
        addsd   xmm2, [edx]
        add     edx, 8
        dec     ecx
        jnz     .horner
        movsd   xmm1, xmm0
        mulsd   xmm1, xmm0              ; r^2
        mulsd   xmm1, xmm2
        addsd   xmm0, xmm1
        addsd   xmm0, [f64_one]
        add     eax, 1023               ; 2^k, built from its bits
        shl     eax, 20
        mov     dword [FM_X], 0
        mov     [FM_X+4], eax
        mulsd   xmm0, [FM_X]
        ret

align 16
abs64:   dq 0x7FFFFFFFFFFFFFFF, 0
tan_pi8: dq 0.4142135623730951
pi_4:    dq 0.7853981633974483
pi_2:    dq 1.5707963267948966
pi:      dq 3.141592653589793
inv_ln2: dq 1.4426950408889634
ln2_hi:  dq 6.93147180369123816490e-01
ln2_lo:  dq 1.90821492927058770002e-10
exp_c:   dq 1.1470745597729725e-11  ; 1/14!
         dq 1.6059043836821613e-10  ; 1/13!
         dq 2.08767569878681e-9     ; 1/12!
         dq 2.505210838544172e-8    ; 1/11!
         dq 2.755731922398589e-7    ; 1/10!
         dq 2.7557319223985893e-6   ; 1/9!
         dq 2.48015873015873e-5     ; 1/8!
         dq 1.984126984126984e-4    ; 1/7!
         dq 1.388888888888889e-3    ; 1/6!
         dq 8.333333333333333e-3    ; 1/5!
         dq 4.1666666666666664e-2   ; 1/4!
         dq 0.16666666666666666     ; 1/3!
         dq 0.5                     ; 1/2!
f32_2pi: dd 6.2831855               ; (float)(2*pi)
