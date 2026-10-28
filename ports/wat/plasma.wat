;; PLASMA: four summed sine fields, the oldest trick in the demoscene book
;;
;; The ladder: rung 1 calls a real sine (our $sin64) four times per pixel,
;; rung 2 reads the sine table four times per pixel, rung 3 (the default)
;; moves three of the four lookups into 1D tables rebuilt once per frame.

;; where the tables live in SCRATCH, set by plasma_start
(global $pl_rad (mut i32) (i32.const 0))   ;; w*h f32: distance to the centre, scaled
(global $pl_sx  (mut i32) (i32.const 0))   ;; w f32
(global $pl_sy  (mut i32) (i32.const 0))   ;; h f32
(global $pl_sxy (mut i32) (i32.const 0))   ;; w+h f32
;; per-frame values, set by plasma_prepare
(global $pl_t     (mut f32) (f32.const 0))
(global $pl_kx    (mut f32) (f32.const 0))
(global $pl_ky    (mut f32) (f32.const 0))
(global $pl_kr    (mut f32) (f32.const 0))
(global $pl_cx    (mut f32) (f32.const 0))
(global $pl_cy    (mut f32) (f32.const 0))
(global $pl_phase (mut f32) (f32.const 0))

;; plasma_start is Go's Resize: the radial distance never changes, so it is
;; computed once per pixel here and only looked up afterwards.
(func $plasma_start
  (local $x i32) (local $y i32) (local $p i32)
  (local $cx f32) (local $cy f32) (local $k f32) (local $dx f32) (local $dy f32)
  (local $wh i32)
  (local.set $wh (i32.mul (global.get $W) (global.get $H)))
  (global.set $pl_rad (global.get $SCRATCH))
  (global.set $pl_sx  (i32.add (global.get $pl_rad) (i32.shl (local.get $wh) (i32.const 2))))
  (global.set $pl_sy  (i32.add (global.get $pl_sx) (i32.shl (global.get $W) (i32.const 2))))
  (global.set $pl_sxy (i32.add (global.get $pl_sy) (i32.shl (global.get $H) (i32.const 2))))
  (local.set $cx (f32.mul (f32.convert_i32_s (global.get $W)) (f32.const 0.5)))
  (local.set $cy (f32.mul (f32.convert_i32_s (global.get $H)) (f32.const 0.5)))
  (local.set $k (f32.div (f32.const 44)
                         (f32.convert_i32_s (i32.add (global.get $W) (global.get $H)))))
  (local.set $p (global.get $pl_rad))
  (loop $rows
    (local.set $dy (f32.sub (f32.convert_i32_s (local.get $y)) (local.get $cy)))
    (local.set $x (i32.const 0))
    (loop $cols
      (local.set $dx (f32.sub (f32.convert_i32_s (local.get $x)) (local.get $cx)))
      ;; f32.sqrt is correctly rounded, so it equals Go's float32(math.Sqrt(...))
      (f32.store (local.get $p)
        (f32.mul (f32.sqrt (f32.add (f32.mul (local.get $dx) (local.get $dx))
                                    (f32.mul (local.get $dy) (local.get $dy))))
                 (local.get $k)))
      (local.set $p (i32.add (local.get $p) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H)))))

;; plasma_prepare fills the three 1D tables for this frame. $t arrives as
;; Go's float32(s.Beat): the f64 n/60, demoted. Computing n/60 in f32 instead
;; would round differently and shift the whole picture by a hair.
(func $plasma_prepare (param $t f32)
  (local $i i32) (local $n i32) (local $kx f32) (local $ky f32)
  (local.set $kx (f32.div (f32.const 26) (f32.convert_i32_s (global.get $W))))
  (local.set $ky (f32.div (f32.const 26) (f32.convert_i32_s (global.get $H))))
  ;; sx[x] = sin(x*kx + t*1.3)
  (loop $sx
    (f32.store (i32.add (global.get $pl_sx) (i32.shl (local.get $i) (i32.const 2)))
      (call $sin (f32.add (f32.mul (f32.convert_i32_s (local.get $i)) (local.get $kx))
                          (f32.mul (local.get $t) (f32.const 1.3)))))
    (local.set $i (i32.add (local.get $i) (i32.const 1)))
    (br_if $sx (i32.lt_s (local.get $i) (global.get $W))))
  ;; sy[y] = sin(y*ky*1.35 - t*1.1)
  (local.set $i (i32.const 0))
  (loop $sy
    (f32.store (i32.add (global.get $pl_sy) (i32.shl (local.get $i) (i32.const 2)))
      (call $sin (f32.sub (f32.mul (f32.mul (f32.convert_i32_s (local.get $i)) (local.get $ky))
                                   (f32.const 1.35))
                          (f32.mul (local.get $t) (f32.const 1.1)))))
    (local.set $i (i32.add (local.get $i) (i32.const 1)))
    (br_if $sy (i32.lt_s (local.get $i) (global.get $H))))
  ;; sxy[i] = sin(i*kx*0.85 + t*0.8), for i = x + y
  (local.set $n (i32.add (global.get $W) (global.get $H)))
  (local.set $i (i32.const 0))
  (loop $sxy
    (f32.store (i32.add (global.get $pl_sxy) (i32.shl (local.get $i) (i32.const 2)))
      (call $sin (f32.add (f32.mul (f32.mul (f32.convert_i32_s (local.get $i)) (local.get $kx))
                                   (f32.const 0.85))
                          (f32.mul (local.get $t) (f32.const 0.8)))))
    (local.set $i (i32.add (local.get $i) (i32.const 1)))
    (br_if $sxy (i32.lt_s (local.get $i) (local.get $n))))
  (global.set $pl_phase (f32.mul (local.get $t) (f32.const 2.6)))
  (global.set $pl_t (local.get $t))
  (global.set $pl_kx (local.get $kx))
  (global.set $pl_ky (local.get $ky))
  (global.set $pl_cx (f32.mul (f32.convert_i32_s (global.get $W)) (f32.const 0.5)))
  (global.set $pl_cy (f32.mul (f32.convert_i32_s (global.get $H)) (f32.const 0.5)))
  (global.set $pl_kr (f32.div (f32.const 44)
                              (f32.convert_i32_s (i32.add (global.get $W) (global.get $H))))))

;; plasma_colour turns the summed field into a palette index: v*36 + 127.5,
;; truncated toward zero, clamped to 0..255. Then the palette load.
(func $plasma_colour (param $v f32) (result i32)
  (local $i i32)
  (local.set $i (i32.trunc_f32_s (f32.add (f32.mul (local.get $v) (f32.const 36))
                                          (f32.const 127.5))))
  (local.set $i (select (i32.const 0) (local.get $i) (i32.lt_s (local.get $i) (i32.const 0))))
  (local.set $i (select (i32.const 255) (local.get $i) (i32.gt_s (local.get $i) (i32.const 255))))
  (i32.load offset=0x13000 (i32.shl (local.get $i) (i32.const 2))))   ;; SUNSET

;; the default rung. No x or y in the inner loop: four pointers walk the
;; framebuffer, rad, sx and sxy side by side, 4 bytes per pixel. sxy starts
;; at sxy + 4*y, so sxy[x] there is the table's entry x + y: Go's slice
;; p.sxy[y : y+w], as plain address arithmetic.
(func $plasma_draw
  (local $y i32) (local $px i32) (local $end i32)
  (local $rad i32) (local $sx i32) (local $sxy i32)
  (local $sy f32) (local $phase f32) (local $v f32) (local $i i32)
  (local.set $phase (global.get $pl_phase))
  (local.set $px (i32.const 0x120000))                ;; FRAMEBUFFER
  (local.set $rad (global.get $pl_rad))
  ;; @excerpt PLASMA
  (loop $rows
    (local.set $sy (f32.load (i32.add (global.get $pl_sy) (i32.shl (local.get $y) (i32.const 2)))))
    (local.set $sxy (i32.add (global.get $pl_sxy) (i32.shl (local.get $y) (i32.const 2))))
    (local.set $sx (global.get $pl_sx))
    (local.set $end (i32.add (local.get $px) (i32.shl (global.get $W) (i32.const 2))))
    (loop $cols
      ;; v = sx[x] + sy + sxy[x] + sin(rad[x] + phase), added left to right
      (local.set $v
        (f32.add
          (f32.add (f32.add (f32.load (local.get $sx)) (local.get $sy))
                   (f32.load (local.get $sxy)))
          (call $sin (f32.add (f32.load (local.get $rad)) (local.get $phase)))))
      (local.set $i (i32.trunc_f32_s (f32.add (f32.mul (local.get $v) (f32.const 36))
                                              (f32.const 127.5))))
      ;; clamp to 0..255 without a branch: select keeps its first operand
      ;; when the condition is non-zero
      (local.set $i (select (i32.const 0) (local.get $i)
                            (i32.lt_s (local.get $i) (i32.const 0))))
      (local.set $i (select (i32.const 255) (local.get $i)
                            (i32.gt_s (local.get $i) (i32.const 255))))
      (i32.store (local.get $px)
                 (i32.load offset=0x13000 (i32.shl (local.get $i) (i32.const 2))))  ;; SUNSET[i]
      (local.set $px  (i32.add (local.get $px)  (i32.const 4)))
      (local.set $rad (i32.add (local.get $rad) (i32.const 4)))
      (local.set $sx  (i32.add (local.get $sx)  (i32.const 4)))
      (local.set $sxy (i32.add (local.get $sxy) (i32.const 4)))
      (br_if $cols (i32.lt_u (local.get $px) (local.get $end))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H))))
  ;; @end
  )

;; sin32 is a real sine, rounded to f32 like the table: Go's
;; float32(math.Sin(float64(a))), with our own $sin64 for math.Sin.
(func $sin32 (param $a f32) (result f32)
  (f32.demote_f64 (call $sin64 (f64.promote_f32 (local.get $a)))))

;; rung 1: every term, every pixel, from the "maths library". Slow, and the
;; reference for what the table approximates.
(func $plasma_draw_sin
  (local $x i32) (local $y i32) (local $px i32)
  (local $fx f32) (local $fy f32) (local $dx f32) (local $dy f32) (local $rad f32)
  (local $t f32) (local $kx f32) (local $ky f32) (local $kr f32)
  (local.set $t (global.get $pl_t))
  (local.set $kx (global.get $pl_kx))
  (local.set $ky (global.get $pl_ky))
  (local.set $kr (global.get $pl_kr))
  (local.set $px (i32.const 0x120000))
  ;; @excerpt PLASMA/1
  (loop $rows
    (local.set $fy (f32.convert_i32_s (local.get $y)))
    (local.set $dy (f32.sub (local.get $fy) (global.get $pl_cy)))
    (local.set $x (i32.const 0))
    (loop $cols
      (local.set $fx (f32.convert_i32_s (local.get $x)))
      (local.set $dx (f32.sub (local.get $fx) (global.get $pl_cx)))
      (local.set $rad (f32.mul (f32.sqrt (f32.add (f32.mul (local.get $dx) (local.get $dx))
                                                  (f32.mul (local.get $dy) (local.get $dy))))
                               (local.get $kr)))
      (i32.store (local.get $px)
        (call $plasma_colour
          (f32.add
            (f32.add
              (f32.add
                (call $sin32 (f32.add (f32.mul (local.get $fx) (local.get $kx))
                                      (f32.mul (local.get $t) (f32.const 1.3))))
                (call $sin32 (f32.sub (f32.mul (f32.mul (local.get $fy) (local.get $ky))
                                               (f32.const 1.35))
                                      (f32.mul (local.get $t) (f32.const 1.1)))))
              (call $sin32 (f32.add (f32.mul (f32.mul (f32.convert_i32_s
                                                        (i32.add (local.get $x) (local.get $y)))
                                                      (local.get $kx))
                                             (f32.const 0.85))
                                    (f32.mul (local.get $t) (f32.const 0.8)))))
            (call $sin32 (f32.add (local.get $rad) (global.get $pl_phase))))))
      (local.set $px (i32.add (local.get $px) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H))))
  ;; @end
  )

;; rung 2: the same per-pixel structure, but the table instead of sin().
;; Same arguments as the default rung, so the same pixels.
(func $plasma_draw_table
  (local $x i32) (local $y i32) (local $px i32)
  (local $fx f32) (local $fy f32) (local $dx f32) (local $dy f32) (local $rad f32)
  (local $t f32) (local $kx f32) (local $ky f32) (local $kr f32)
  (local.set $t (global.get $pl_t))
  (local.set $kx (global.get $pl_kx))
  (local.set $ky (global.get $pl_ky))
  (local.set $kr (global.get $pl_kr))
  (local.set $px (i32.const 0x120000))
  ;; @excerpt PLASMA/2
  (loop $rows
    (local.set $fy (f32.convert_i32_s (local.get $y)))
    (local.set $dy (f32.sub (local.get $fy) (global.get $pl_cy)))
    (local.set $x (i32.const 0))
    (loop $cols
      (local.set $fx (f32.convert_i32_s (local.get $x)))
      (local.set $dx (f32.sub (local.get $fx) (global.get $pl_cx)))
      (local.set $rad (f32.mul (f32.sqrt (f32.add (f32.mul (local.get $dx) (local.get $dx))
                                                  (f32.mul (local.get $dy) (local.get $dy))))
                               (local.get $kr)))
      (i32.store (local.get $px)
        (call $plasma_colour
          (f32.add
            (f32.add
              (f32.add
                (call $sin (f32.add (f32.mul (local.get $fx) (local.get $kx))
                                    (f32.mul (local.get $t) (f32.const 1.3))))
                (call $sin (f32.sub (f32.mul (f32.mul (local.get $fy) (local.get $ky))
                                             (f32.const 1.35))
                                    (f32.mul (local.get $t) (f32.const 1.1)))))
              (call $sin (f32.add (f32.mul (f32.mul (f32.convert_i32_s
                                                      (i32.add (local.get $x) (local.get $y)))
                                                    (local.get $kx))
                                           (f32.const 0.85))
                                  (f32.mul (local.get $t) (f32.const 0.8)))))
            (call $sin (f32.add (local.get $rad) (global.get $pl_phase))))))
      (local.set $px (i32.add (local.get $px) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H))))
  ;; @end
  )

(func $plasma_render (param $t f32)
  (call $plasma_prepare (local.get $t))
  (if (i32.eq (global.get $rung) (i32.const 1))
    (then (call $plasma_draw_sin) (return)))
  (if (i32.eq (global.get $rung) (i32.const 2))
    (then (call $plasma_draw_table) (return)))
  (call $plasma_draw))
