;; fmath: the maths library WebAssembly does not have
;;
;; wasm's floating-point instructions stop at + - * / sqrt, abs, neg,
;; copysign, min, max, ceil, floor, trunc and nearest. There is no sin, no
;; cos, no atan2, no exp: the libm a compiler links into its .wasm is plain
;; code made of those instructions. Here we write that code by hand: short
;; Taylor series behind a range reduction, in f64, which is far more than the
;; f32 tables and the 8-bit colours below need.
;;
;; Then the demoscene part: the effects never call sin() per pixel anyway.
;; They read an 8192-step table built once at start-up, exactly like Go's
;; fmath.SinTab. Our table is computed, not shipped: a data segment would be
;; 64 KiB of the module; the code that builds it is a few hundred bytes.

;; ---------------------------------------------------------------------------
;; sin and cos, f64
;; ---------------------------------------------------------------------------

;; reduce_pio2 writes x = k*(pi/2) + r with |r| <= pi/4 and returns r and the
;; quadrant k: two results, left on the stack (multi-value). sin and cos only
;; ever need [-pi/4, pi/4]; the quadrant says which of the two and its sign.
;;
;; pi/2 is split in two (Cody and Waite). PIO2_HI keeps only 33 significant
;; bits, so k*PIO2_HI is exact for every k we meet and x - k*PIO2_HI loses
;; nothing; PIO2_LO = pi/2 - PIO2_HI then adds the bits the first half
;; dropped. With pi/2 in one piece, sin(pi) would come out as noise.
(func $reduce_pio2 (param $x f64) (result f64 i32)
  (local $k f64)
  (local.set $k (f64.nearest (f64.mul (local.get $x)
                                      (f64.const 0.6366197723675814))))  ;; 2/pi
  (f64.sub
    (f64.sub (local.get $x)
             (f64.mul (local.get $k) (f64.const 1.5707963267341256)))    ;; PIO2_HI
    (f64.mul (local.get $k) (f64.const 6.077100506506192e-11)))          ;; PIO2_LO
  (i32.trunc_f64_s (local.get $k)))

;; ksin and kcos are the Taylor series on |r| <= pi/4, evaluated by Horner's
;; rule in flat stack form: each line is "times z, plus the next
;; coefficient". The first dropped term, r^19/19!, is below 1e-19 there.
;; WebAssembly never fuses a*b+c into one rounding (there is no FMA in the
;; MVP), so every mul and add below rounds exactly once, as written.
(func $ksin (param $r f64) (result f64)
  (local $z f64)
  (local.set $z (f64.mul (local.get $r) (local.get $r)))
  ;; sin r = r + r*z*(-1/3! + z*(1/5! + z*(-1/7! + ...)))
  local.get $r
  local.get $r  local.get $z  f64.mul
  f64.const  2.8114572543455206e-15                               ;;  1/17!
  local.get $z  f64.mul  f64.const -7.647163731819816e-13   f64.add  ;; -1/15!
  local.get $z  f64.mul  f64.const  1.6059043836821613e-10  f64.add  ;;  1/13!
  local.get $z  f64.mul  f64.const -2.505210838544172e-8    f64.add  ;; -1/11!
  local.get $z  f64.mul  f64.const  2.7557319223985893e-6   f64.add  ;;  1/9!
  local.get $z  f64.mul  f64.const -1.984126984126984e-4    f64.add  ;; -1/7!
  local.get $z  f64.mul  f64.const  8.333333333333333e-3    f64.add  ;;  1/5!
  local.get $z  f64.mul  f64.const -0.16666666666666666     f64.add  ;; -1/3!
  f64.mul
  f64.add)

(func $kcos (param $r f64) (result f64)
  (local $z f64)
  (local.set $z (f64.mul (local.get $r) (local.get $r)))
  ;; cos r = 1 + z*(-1/2! + z*(1/4! + z*(-1/6! + ...)))
  f64.const 1
  local.get $z
  f64.const -1.5619206968586225e-16                               ;; -1/18!
  local.get $z  f64.mul  f64.const  4.779477332387385e-14   f64.add  ;;  1/16!
  local.get $z  f64.mul  f64.const -1.1470745597729725e-11  f64.add  ;; -1/14!
  local.get $z  f64.mul  f64.const  2.08767569878681e-9     f64.add  ;;  1/12!
  local.get $z  f64.mul  f64.const -2.755731922398589e-7    f64.add  ;; -1/10!
  local.get $z  f64.mul  f64.const  2.48015873015873e-5     f64.add  ;;  1/8!
  local.get $z  f64.mul  f64.const -1.388888888888889e-3    f64.add  ;; -1/6!
  local.get $z  f64.mul  f64.const  4.1666666666666664e-2   f64.add  ;;  1/4!
  local.get $z  f64.mul  f64.const -0.5                     f64.add  ;; -1/2!
  f64.mul
  f64.add)

;; sin_quadrant: sin(q*pi/2 + r). Odd quadrants swap sin for cos, quadrants
;; 2 and 3 flip the sign. q may be negative: q & 3 is still right, because
;; two's complement makes -1 & 3 == 3.
(func $sin_quadrant (param $r f64) (param $q i32) (result f64)
  (local $v f64)
  (local.set $v
    (if (result f64) (i32.and (local.get $q) (i32.const 1))
      (then (call $kcos (local.get $r)))
      (else (call $ksin (local.get $r)))))
  (select (f64.neg (local.get $v)) (local.get $v)
          (i32.and (local.get $q) (i32.const 2))))

(func $sin64 (param $x f64) (result f64)
  (call $sin_quadrant (call $reduce_pio2 (local.get $x))))

;; cos is sin a quarter turn later: the same r, the next quadrant.
(func $cos64 (param $x f64) (result f64)
  (local $q i32)
  (call $reduce_pio2 (local.get $x))
  (local.set $q)                       ;; the i32 is on top of the stack
  (i32.add (local.get $q) (i32.const 1))
  (call $sin_quadrant))

;; ---------------------------------------------------------------------------
;; the sine tables
;; ---------------------------------------------------------------------------

;; build_sine_tables is Go's fmath.init: the angle is computed in f64 exactly
;; as Go writes it, 2*pi*i/8192, then sin and cos are rounded to f32 with
;; f32.demote_f64. Our sin64 is not Go's math.Sin, but both are within an f64
;; ulp or two of the truth, and that rarely survives rounding to f32's 24 bits.
;; (Measured: all 8193 entries of both tables equal Go's, bit for bit.)
(func $build_sine_tables
  (local $i i32) (local $a f64) (local $p i32)
  (loop $each
    (local.set $a (f64.div (f64.mul (f64.const 6.283185307179586)  ;; 2*pi
                                    (f64.convert_i32_s (local.get $i)))
                           (f64.const 8192)))
    (local.set $p (i32.shl (local.get $i) (i32.const 2)))
    (f32.store offset=0x1000 (local.get $p) (f32.demote_f64 (call $sin64 (local.get $a))))
    (f32.store offset=0xA000 (local.get $p) (f32.demote_f64 (call $cos64 (local.get $a))))
    (local.set $i (i32.add (local.get $i) (i32.const 1)))
    (br_if $each (i32.lt_u (local.get $i) (i32.const 8192))))
  ;; a full period overflows exactly: entry 8192 is entry 0
  (f32.store offset=0x9000 (i32.const 0) (f32.load offset=0x1000 (i32.const 0)))
  (f32.store offset=0x12000 (i32.const 0) (f32.load offset=0xA000 (i32.const 0))))

;; sin, cos, sin01, cos01 are Go's fmath.Sin and friends: turn the angle into
;; a table index, truncate, wrap with & 8191, load. That is the whole cost of
;; a sine in every scene's hot loop.
;;
;; i32.trunc_f32_s truncates toward zero, as Go's int() does, and traps on a
;; value it cannot represent (NaN, or beyond 2^31). Its sibling
;; i32.trunc_sat_f32_s (the saturating-float-to-int feature) clamps instead.
;; Go's values are always in range here, so the plain MVP instruction gives
;; the same bits, and a trap would be a bug worth seeing. A negative index
;; wraps the same way as in Go: -3 & 8191 == 8189 in two's complement.
(func $sin (param $a f32) (result f32)
  (f32.load offset=0x1000
    (i32.shl
      (i32.and (i32.trunc_f32_s (f32.mul (local.get $a)
                                         (f32.const 1303.7972412109375)))  ;; 8192/(2*pi), as f32
               (i32.const 8191))
      (i32.const 2))))

(func $cos (param $a f32) (result f32)
  (f32.load offset=0xA000
    (i32.shl
      (i32.and (i32.trunc_f32_s (f32.mul (local.get $a)
                                         (f32.const 1303.7972412109375)))
               (i32.const 8191))
      (i32.const 2))))

;; t in turns rather than radians: the index is just t*8192
(func $sin01 (param $t f32) (result f32)
  (f32.load offset=0x1000
    (i32.shl
      (i32.and (i32.trunc_f32_s (f32.mul (local.get $t) (f32.const 8192)))
               (i32.const 8191))
      (i32.const 2))))

;; ---------------------------------------------------------------------------
;; atan2, f64
;; ---------------------------------------------------------------------------

;; build_atan_series stores the Taylor coefficients of atan,
;; atan z = z - z^3/3 + z^5/5 - ..., as (-1)^k / (2k+1) for k = 0..20.
;; Each one is a single correctly rounded division.
(func $build_atan_series
  (local $k i32)
  (loop $each
    (f64.store offset=0x400 (i32.shl (local.get $k) (i32.const 3))
      (f64.div
        (select (f64.const -1) (f64.const 1) (i32.and (local.get $k) (i32.const 1)))
        (f64.convert_i32_s (i32.add (i32.shl (local.get $k) (i32.const 1)) (i32.const 1)))))
    (local.set $k (i32.add (local.get $k) (i32.const 1)))
    (br_if $each (i32.le_u (local.get $k) (i32.const 20)))))

;; atan01 is atan(t) for t in [0, 1]. The series converges slowly near 1, so
;; above tan(pi/8) we use atan t = pi/4 + atan((t-1)/(t+1)), which brings the
;; argument back under 0.4143. There, 21 terms leave an error below 1e-18.
(func $atan01 (param $t f64) (result f64)
  (local $base f64) (local $z f64) (local $z2 f64) (local $acc f64) (local $k i32)
  (local.set $z (local.get $t))
  (if (f64.gt (local.get $t) (f64.const 0.4142135623730951))   ;; tan(pi/8)
    (then
      (local.set $base (f64.const 0.7853981633974483))         ;; pi/4
      (local.set $z (f64.div (f64.sub (local.get $t) (f64.const 1))
                             (f64.add (local.get $t) (f64.const 1))))))
  (local.set $z2 (f64.mul (local.get $z) (local.get $z)))
  ;; Horner from the highest coefficient down: acc = acc*z^2 + c[k]
  (local.set $k (i32.const 160))                               ;; 20 * 8 bytes
  (loop $term
    (local.set $acc (f64.add (f64.mul (local.get $acc) (local.get $z2))
                             (f64.load offset=0x400 (local.get $k))))
    (local.set $k (i32.sub (local.get $k) (i32.const 8)))
    (br_if $term (i32.ge_s (local.get $k) (i32.const 0))))
  (f64.add (local.get $base) (f64.mul (local.get $z) (local.get $acc))))

;; atan2 folds the plane onto the first octant, where atan01 works, and
;; unfolds the answer: swap x and y above the diagonal (pi/2 - a), mirror
;; for x < 0 (pi - a), and take the sign of y. copysign reads the sign bit,
;; so -0 counts as negative, as in Go: atan2(+0, -0) = pi.
(func $atan2 (param $y f64) (param $x f64) (result f64)
  (local $ax f64) (local $ay f64) (local $a f64)
  (local.set $ax (f64.abs (local.get $x)))
  (local.set $ay (f64.abs (local.get $y)))
  (if (f64.le (local.get $ay) (local.get $ax))
    (then
      (if (f64.gt (local.get $ax) (f64.const 0))           ;; atan2(0, 0) is 0
        (then (local.set $a (call $atan01 (f64.div (local.get $ay) (local.get $ax)))))))
    (else
      (local.set $a (f64.sub (f64.const 1.5707963267948966)  ;; pi/2
                             (call $atan01 (f64.div (local.get $ax) (local.get $ay)))))))
  (if (f64.lt (f64.copysign (f64.const 1) (local.get $x)) (f64.const 0))
    (then (local.set $a (f64.sub (f64.const 3.141592653589793) (local.get $a)))))
  (f64.copysign (local.get $a) (local.get $y)))

;; ---------------------------------------------------------------------------
;; exp, f64
;; ---------------------------------------------------------------------------

;; exp x = 2^k * e^r, with k the nearest integer to x/ln2 and |r| <= ln2/2.
;; ln2 is split in two, as pi/2 was. e^r is 1 + (r + r^2/2! + ... + r^14/14!):
;; the small part is summed first and the 1 added last, so its rounding
;; errors fall below the result's last bit. 2^k needs no arithmetic at all:
;; it is the f64 whose exponent field is k + 1023, built from the bits.
(func $exp (param $x f64) (result f64)
  (local $k f64) (local $r f64)
  (local.set $k (f64.nearest (f64.mul (local.get $x) (f64.const 1.4426950408889634))))  ;; 1/ln2
  (local.set $r
    (f64.sub (f64.sub (local.get $x)
                      (f64.mul (local.get $k) (f64.const 6.93147180369123816490e-01)))  ;; LN2_HI
             (f64.mul (local.get $k) (f64.const 1.90821492927058770002e-10))))          ;; LN2_LO
  f64.const 1
  local.get $r
  local.get $r  local.get $r  f64.mul
  f64.const 1.1470745597729725e-11                                 ;; 1/14!
  local.get $r  f64.mul  f64.const 1.6059043836821613e-10  f64.add  ;; 1/13!
  local.get $r  f64.mul  f64.const 2.08767569878681e-9     f64.add  ;; 1/12!
  local.get $r  f64.mul  f64.const 2.505210838544172e-8    f64.add  ;; 1/11!
  local.get $r  f64.mul  f64.const 2.755731922398589e-7    f64.add  ;; 1/10!
  local.get $r  f64.mul  f64.const 2.7557319223985893e-6   f64.add  ;; 1/9!
  local.get $r  f64.mul  f64.const 2.48015873015873e-5     f64.add  ;; 1/8!
  local.get $r  f64.mul  f64.const 1.984126984126984e-4    f64.add  ;; 1/7!
  local.get $r  f64.mul  f64.const 1.388888888888889e-3    f64.add  ;; 1/6!
  local.get $r  f64.mul  f64.const 8.333333333333333e-3    f64.add  ;; 1/5!
  local.get $r  f64.mul  f64.const 4.1666666666666664e-2   f64.add  ;; 1/4!
  local.get $r  f64.mul  f64.const 0.16666666666666666     f64.add  ;; 1/3!
  local.get $r  f64.mul  f64.const 0.5                     f64.add  ;; 1/2!
  f64.mul                   ;; r^2 * (...)
  f64.add                   ;; r + r^2 * (...)
  f64.add                   ;; 1 + ...
  ;; times 2^k: the bit pattern (k + 1023) << 52
  (f64.reinterpret_i64
    (i64.shl (i64.add (i64.trunc_f64_s (local.get $k)) (i64.const 1023))
             (i64.const 52)))
  f64.mul)
