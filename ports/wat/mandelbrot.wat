;; MANDELBROT: an endless dive into the seahorse valley, all in f64
;;
;; The ladder: rung 1 iterates every pixel with no shortcut, rung 2 adds the
;; closed-form test for the cardioid and the period-2 bulb, rung 3 (the
;; default) also renders blocks of 2x2 pixels (3x3 above 1600 wide).

(global $mb_block (mut i32) (i32.const 2))

(func $mandelbrot_start
  (global.set $mb_block (select (i32.const 3) (i32.const 2)
                                (i32.gt_s (global.get $W) (i32.const 1600)))))

;; @excerpt MANDELBROT/1
;; the escape-time loop and nothing else: a point inside the set runs the
;; whole budget before giving up
(func $mandel_iter_plain (param $cx f64) (param $cy f64) (param $max i32) (result i32)
  (local $i i32) (local $zx f64) (local $zy f64) (local $zx2 f64) (local $zy2 f64)
  (block $inside
    (loop $iterate
      (br_if $inside (i32.ge_s (local.get $i) (local.get $max)))
      ;; zy = 2*zx*zy + cy, then zx = zx^2 - zy^2 + cx
      (local.set $zy (f64.add (f64.mul (f64.mul (f64.const 2) (local.get $zx)) (local.get $zy))
                              (local.get $cy)))
      (local.set $zx (f64.add (f64.sub (local.get $zx2) (local.get $zy2)) (local.get $cx)))
      (local.set $zx2 (f64.mul (local.get $zx) (local.get $zx)))
      (local.set $zy2 (f64.mul (local.get $zy) (local.get $zy)))
      (if (f64.gt (f64.add (local.get $zx2) (local.get $zy2)) (f64.const 4))
        (then (return (local.get $i))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $iterate)))
  (local.get $max))
;; @end

;; @excerpt MANDELBROT/2
(func $mandel_iter (param $cx f64) (param $cy f64) (param $max i32) (result i32)
  (local $x f64) (local $y2 f64) (local $q f64)
  ;; cheap escape test for the main cardioid ...
  (local.set $x (f64.sub (local.get $cx) (f64.const 0.25)))
  (local.set $y2 (f64.mul (local.get $cy) (local.get $cy)))
  (local.set $q (f64.add (f64.mul (local.get $x) (local.get $x)) (local.get $y2)))
  (if (f64.le (f64.mul (local.get $q) (f64.add (local.get $q) (local.get $x)))
              (f64.mul (f64.const 0.25) (local.get $y2)))
    (then (return (local.get $max))))
  ;; ... and for the period-2 bulb
  (if (f64.le (f64.add (f64.mul (f64.add (local.get $cx) (f64.const 1))
                                (f64.add (local.get $cx) (f64.const 1)))
                       (local.get $y2))
              (f64.const 0.0625))
    (then (return (local.get $max))))
  (call $mandel_iter_plain (local.get $cx) (local.get $cy) (local.get $max)))
;; @end

(func $mandelbrot_render (param $t f64)
  (local $u f64) (local $k f64) (local $scale f64) (local $maxIter i32)
  (local $cx f64) (local $cy f64) (local $x0 f64) (local $y0 f64) (local $d f64)
  (local $block i32) (local $x i32) (local $y i32) (local $xx i32) (local $yy i32)
  (local $xEnd i32) (local $yEnd i32) (local $it i32) (local $c i32) (local $v f64)
  (local $idx i32) (local $row i32) (local $rowBytes i32)
  ;; Prepare: the camera slides onto the target fast, then the exponential
  ;; zoom does the work. $exp is the port's own, in fmath.wat.
  (local.set $u (f64.div (f64.min (local.get $t) (f64.const 14)) (f64.const 12)))
  (local.set $k (f64.sub (f64.const 1) (call $exp (f64.mul (f64.const -8) (local.get $u)))))
  (local.set $scale (f64.mul (f64.const 2.9)
                             (call $exp (f64.mul (f64.mul (f64.neg (local.get $u)) (local.get $u))
                                                 (f64.const 3.6)))))
  (local.set $maxIter (i32.add (i32.const 64)
                               (i32.trunc_f64_s (f64.mul (f64.const 128) (local.get $u)))))
  ;; Go folds -0.743643887037151 + 0.5 at compile time, exactly
  (local.set $cx (f64.add (f64.const -0.5)
                          (f64.mul (f64.const -0.243643887037151) (local.get $k))))
  (local.set $cy (f64.mul (f64.const 0.131825904205330) (local.get $k)))

  ;; Draw: the view, in plane units per pixel
  (local.set $block (global.get $mb_block))
  (if (i32.ne (global.get $rung) (i32.const 0))
    (then (if (i32.lt_u (global.get $rung) (i32.const 3))
      (then (local.set $block (i32.const 1))))))
  (local.set $x0 (f64.sub (local.get $cx) (f64.mul (local.get $scale) (f64.const 0.5))))
  (local.set $y0 (f64.sub (local.get $cy)
                          (f64.mul (f64.mul (local.get $scale) (f64.const 0.5))
                                   (f64.div (f64.convert_i32_s (global.get $H))
                                            (f64.convert_i32_s (global.get $W))))))
  (local.set $d (f64.div (local.get $scale) (f64.convert_i32_s (global.get $W))))
  (local.set $rowBytes (i32.shl (global.get $W) (i32.const 2)))
  ;; @excerpt MANDELBROT
  (loop $rows
    (local.set $yEnd (i32.add (local.get $y) (local.get $block)))
    (local.set $yEnd (select (global.get $H) (local.get $yEnd)
                             (i32.gt_s (local.get $yEnd) (global.get $H))))
    (local.set $row (i32.add (i32.const 0x120000) (i32.mul (local.get $y) (local.get $rowBytes))))
    (local.set $x (i32.const 0))
    (loop $cols
      ;; rung 1 is the plain loop; the others try the closed forms first
      (local.set $it
        (if (result i32) (i32.eq (global.get $rung) (i32.const 1))
          (then (call $mandel_iter_plain
                  (f64.add (local.get $x0) (f64.mul (f64.convert_i32_s (local.get $x)) (local.get $d)))
                  (f64.add (local.get $y0) (f64.mul (f64.convert_i32_s (local.get $y)) (local.get $d)))
                  (local.get $maxIter)))
          (else (call $mandel_iter
                  (f64.add (local.get $x0) (f64.mul (f64.convert_i32_s (local.get $x)) (local.get $d)))
                  (f64.add (local.get $y0) (f64.mul (f64.convert_i32_s (local.get $y)) (local.get $d)))
                  (local.get $maxIter)))))
      (if (i32.ge_s (local.get $it) (local.get $maxIter))
        (then (local.set $c (i32.const 0xFF0A0812)))
        (else
          ;; the ramp is anchored to 40 iterations, not to the budget, so a
          ;; deeper zoom does not darken the picture: ICE[sqrt(it/40)*0.92+0.04]
          (local.set $v (f64.min (f64.sqrt (f64.div (f64.convert_i32_s (local.get $it))
                                                    (f64.const 40)))
                                 (f64.const 1)))
          (local.set $idx (i32.trunc_f64_s
                            (f64.mul (f64.add (f64.mul (local.get $v) (f64.const 0.92))
                                              (f64.const 0.04))
                                     (f64.const 255))))
          (local.set $c (i32.load offset=0x13400 (i32.shl (local.get $idx) (i32.const 2))))))
      ;; one row of the block now; the rows below are copied afterwards
      (local.set $xEnd (i32.add (local.get $x) (local.get $block)))
      (local.set $xEnd (select (global.get $W) (local.get $xEnd)
                               (i32.gt_s (local.get $xEnd) (global.get $W))))
      (local.set $xx (local.get $x))
      (loop $fill
        (i32.store (i32.add (local.get $row) (i32.shl (local.get $xx) (i32.const 2)))
                   (local.get $c))
        (local.set $xx (i32.add (local.get $xx) (i32.const 1)))
        (br_if $fill (i32.lt_s (local.get $xx) (local.get $xEnd))))
      (local.set $x (local.get $xEnd))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    ;; the other rows of the block are the same pixels: memory.copy, the
    ;; engine's memmove, one instruction per row
    (local.set $yy (i32.add (local.get $y) (i32.const 1)))
    (block $copied
      (loop $copy
        (br_if $copied (i32.ge_s (local.get $yy) (local.get $yEnd)))
        (memory.copy (i32.add (local.get $row)
                              (i32.mul (i32.sub (local.get $yy) (local.get $y)) (local.get $rowBytes)))
                     (local.get $row) (local.get $rowBytes))
        (local.set $yy (i32.add (local.get $yy) (i32.const 1)))
        (br $copy)))
    (local.set $y (local.get $yEnd))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H))))
  ;; @end
  )
