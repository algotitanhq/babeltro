;; GRID: the synthwave floor rushing at the camera under a banded sun
;;
;; The scene that mixes f32 and f64 the most: Go clamps and builds some
;; colours in f64 (canvas.Clamp01 takes a float64) and does the rest in f32.
;; Every f64.promote_f32 and f32.demote_f64 below is a conversion Go writes
;; out; none of them can be left implicit, because WebAssembly has none.

;; Clamp01 in f64. min and max are Go's two comparisons for any non-NaN input.
(func $clamp01 (param $v f64) (result f64)
  (f64.min (f64.max (local.get $v) (f64.const 0)) (f64.const 1)))

;; clamp01 of an f32 expression, back in f32: float32(Clamp01(float64(v)))
(func $clamp01f (param $v f32) (result f32)
  (f32.demote_f64 (call $clamp01 (f64.promote_f32 (local.get $v)))))

;; mathMod2: v mod 1 in [0, 1), negatives included
(func $mod1 (param $v f32) (result f32)
  (local $m f32)
  (local.set $m (f32.sub (local.get $v) (f32.convert_i32_s (i32.trunc_f32_s (local.get $v)))))
  (select (f32.add (local.get $m) (f32.const 1)) (local.get $m)
          (f32.lt (local.get $m) (f32.const 0))))

;; lineGlow: 1 on the grid line, falling to 0 over width w
(func $line_glow (param $f f32) (param $w f32) (result f32)
  (if (f32.gt (local.get $f) (f32.const 0.5))
    (then (local.set $f (f32.sub (f32.const 1) (local.get $f)))))
  (if (result f32) (f32.lt (local.get $f) (local.get $w))
    (then (f32.sub (f32.const 1) (f32.div (local.get $f) (local.get $w))))
    (else (f32.const 0))))

(func $grid_render (param $t f32)
  (local $x i32) (local $y i32) (local $px i32)
  (local $fw f32) (local $fh f32) (local $horizon f32) (local $asp f32) (local $cx f32)
  (local $sunY f32) (local $sunR f32) (local $fy f32) (local $fx f32)
  (local $sky f64) (local $skyR f32) (local $skyG f32) (local $skyB f32)
  (local $onFloor i32) (local $floorR f32) (local $floorG f32) (local $floorB f32)
  (local $kx f32) (local $dz f32) (local $lineZ f32) (local $fadeX f32) (local $lwX f32)
  (local $z f32) (local $wz f32) (local $period f32) (local $lwZ f32) (local $ampZ f32)
  (local $minW f32) (local $haze f64)
  (local $dyc f32) (local $sunRow i32) (local $stripe i32) (local $u f64)
  (local $sr f32) (local $sg f32) (local $sb f32)
  (local $r f32) (local $g f32) (local $b f32) (local $dx f32) (local $d f32) (local $edge f32)
  (local $off f32) (local $wPx f32) (local $slide f32) (local $lineX f32) (local $line f32)
  (local.set $fw (f32.convert_i32_s (global.get $W)))
  (local.set $fh (f32.convert_i32_s (global.get $H)))
  (local.set $horizon (f32.mul (local.get $fh) (f32.const 0.52)))
  (local.set $asp (f32.div (local.get $fh) (local.get $fw)))
  (local.set $cx (f32.mul (local.get $fw) (f32.const 0.5)))
  (local.set $sunY (f32.sub (local.get $horizon) (f32.mul (local.get $fh) (f32.const 0.13))))
  (local.set $sunR (f32.mul (local.get $fh) (f32.const 0.16)))
  (local.set $lwX (f32.const 0.022))
  (local.set $px (i32.const 0x120000))
  (loop $rows
    (local.set $fy (f32.convert_i32_s (local.get $y)))
    ;; the sky: a ramp per row, in f64, rounded to f32
    (local.set $sky (call $clamp01 (f64.promote_f32 (f32.div (local.get $fy) (local.get $horizon)))))
    (local.set $skyR (f32.demote_f64 (f64.add (f64.const 0.03)
                                              (f64.mul (f64.mul (f64.const 0.18) (local.get $sky)) (local.get $sky)))))
    (local.set $skyG (f32.demote_f64 (f64.add (f64.const 0.01) (f64.mul (f64.const 0.05) (local.get $sky)))))
    (local.set $skyB (f32.demote_f64 (f64.add (f64.const 0.08) (f64.mul (f64.const 0.22) (local.get $sky)))))

    ;; the floor: everything that depends only on the row
    (local.set $onFloor (f32.gt (local.get $fy) (local.get $horizon)))
    (if (local.get $onFloor)
      (then
        (local.set $dz (f32.sub (local.get $fy) (local.get $horizon)))
        (local.set $z (f32.div (f32.mul (local.get $fh) (f32.const 0.55)) (local.get $dz)))
        (local.set $wz (f32.add (f32.mul (local.get $z) (f32.const 2.5)) (f32.mul (local.get $t) (f32.const 5.5))))
        (local.set $kx (f32.mul (f32.mul (f32.div (local.get $z) (f32.mul (local.get $fw) (f32.const 0.5)))
                                         (local.get $asp))
                                (f32.const 2)))
        (local.set $fadeX (call $clamp01f (f32.div (f32.sub (f32.div (f32.const 1) (local.get $kx)) (f32.const 1.5))
                                                   (f32.const 2))))
        ;; a line thinner than a pixel is widened to one pixel and dimmed
        ;; by the area it really covers
        (local.set $period (f32.div (f32.mul (local.get $dz) (local.get $dz))
                                    (f32.mul (f32.const 1.375) (local.get $fh))))
        (local.set $lwZ (f32.add (f32.const 0.014) (f32.div (f32.const 0.024) (local.get $z))))
        (local.set $ampZ (f32.const 1))
        (local.set $minW (f32.div (f32.const 0.5) (local.get $period)))
        (if (f32.lt (local.get $lwZ) (local.get $minW))
          (then (local.set $ampZ (f32.div (local.get $lwZ) (local.get $minW)))
                (local.set $lwZ (local.get $minW))))
        (local.set $lineZ (f32.mul (call $line_glow (call $mod1 (local.get $wz)) (local.get $lwZ))
                                   (local.get $ampZ)))
        (local.set $lineZ (f32.mul (local.get $lineZ)
                                   (call $clamp01f (f32.div (f32.sub (local.get $period) (f32.const 1.5))
                                                            (f32.const 2)))))
        ;; fog
        (local.set $lineZ (f32.mul (local.get $lineZ)
          (call $clamp01f (f32.div (f32.const 1)
                                   (f32.add (f32.const 1) (f32.mul (f32.mul (local.get $z) (local.get $z))
                                                                   (f32.const 0.004)))))))
        (local.set $floorR (f32.const 0.02))
        (local.set $floorG (f32.const 0.01))
        (local.set $floorB (f32.const 0.06))
        ;; the haze near the horizon, computed in f64 and rounded
        (local.set $haze (call $clamp01 (f64.promote_f32 (f32.div (local.get $dz)
                                                                  (f32.mul (local.get $fh) (f32.const 0.12))))))
        (if (f64.lt (local.get $haze) (f64.const 1))
          (then
            (local.set $floorR (f32.add (local.get $floorR)
              (f32.demote_f64 (f64.mul (f64.const 0.25) (f64.sub (f64.const 1) (local.get $haze))))))
            (local.set $floorG (f32.add (local.get $floorG)
              (f32.demote_f64 (f64.mul (f64.const 0.05) (f64.sub (f64.const 1) (local.get $haze))))))
            (local.set $floorB (f32.add (local.get $floorB)
              (f32.demote_f64 (f64.mul (f64.const 0.35) (f64.sub (f64.const 1) (local.get $haze))))))))
        (local.set $floorR (f32.add (local.get $floorR) (f32.mul (f32.const 0.55) (local.get $lineZ))))
        (local.set $floorG (f32.add (local.get $floorG) (f32.mul (f32.const 0.35) (local.get $lineZ))))
        (local.set $floorB (f32.add (local.get $floorB) (f32.mul (f32.const 0.75) (local.get $lineZ))))))

    ;; the sun: a bounding test per row, the circle only inside it
    (local.set $dyc (f32.sub (local.get $fy) (local.get $sunY)))
    (local.set $sunRow (i32.and (i32.and (f32.gt (local.get $dyc) (f32.neg (local.get $sunR)))
                                         (f32.lt (local.get $dyc) (local.get $sunR)))
                                (f32.lt (local.get $fy) (f32.add (local.get $horizon) (f32.const 2)))))
    (local.set $stripe (i32.const 0))
    (if (local.get $sunRow)
      (then
        (local.set $stripe (i32.and (f32.gt (local.get $fy)
                                            (f32.sub (local.get $sunY) (f32.mul (local.get $sunR) (f32.const 0.45))))
                                    (i32.lt_s (i32.rem_s (local.get $y) (i32.const 9)) (i32.const 4))))
        (local.set $u (call $clamp01 (f64.promote_f32
                         (f32.div (f32.sub (local.get $fy) (f32.sub (local.get $sunY) (local.get $sunR)))
                                  (f32.mul (f32.const 2) (local.get $sunR))))))
        (local.set $sr (f32.const 1))
        (local.set $sg (f32.demote_f64 (f64.sub (f64.const 0.95) (f64.mul (f64.const 0.7) (local.get $u)))))
        (local.set $sb (f32.demote_f64 (f64.add (f64.const 0.25) (f64.mul (f64.const 0.55) (local.get $u)))))))

    (local.set $x (i32.const 0))
    ;; @excerpt GRID
    (loop $cols
      (local.set $fx (f32.convert_i32_s (local.get $x)))
      (local.set $r (local.get $skyR))
      (local.set $g (local.get $skyG))
      (local.set $b (local.get $skyB))
      (if (i32.and (local.get $sunRow) (i32.eqz (local.get $stripe)))
        (then
          (local.set $dx (f32.sub (local.get $fx) (local.get $cx)))
          (if (i32.and (f32.gt (local.get $dx) (f32.neg (local.get $sunR))) (f32.lt (local.get $dx) (local.get $sunR)))
            (then
              (local.set $d (f32.sqrt (f32.add (f32.mul (local.get $dx) (local.get $dx))
                                               (f32.mul (local.get $dyc) (local.get $dyc)))))
              (if (f32.lt (local.get $d) (local.get $sunR))
                (then
                  (local.set $edge (call $clamp01f (f32.div (f32.sub (local.get $sunR) (local.get $d))
                                                            (f32.mul (local.get $sunR) (f32.const 0.025)))))
                  ;; mix(a, b, t) = a + (b - a)*t
                  (local.set $r (f32.add (local.get $r) (f32.mul (f32.sub (local.get $sr) (local.get $r)) (local.get $edge))))
                  (local.set $g (f32.add (local.get $g) (f32.mul (f32.sub (local.get $sg) (local.get $g)) (local.get $edge))))
                  (local.set $b (f32.add (local.get $b) (f32.mul (f32.sub (local.get $sb) (local.get $b)) (local.get $edge))))))))))
      (if (local.get $onFloor)
        (then
          ;; the line is at least as wide as the ray slides between rows
          (local.set $off (f32.abs (f32.sub (local.get $fx) (local.get $cx))))
          (local.set $wPx (f32.div (f32.mul (f32.const 2) (local.get $lwX)) (local.get $kx)))
          (local.set $slide (f32.div (local.get $off) (local.get $dz)))
          (if (f32.gt (local.get $slide) (local.get $wPx)) (then (local.set $wPx (local.get $slide))))
          (if (f32.lt (local.get $wPx) (f32.const 1)) (then (local.set $wPx (f32.const 1))))
          (local.set $lineX
            (f32.mul
              (f32.mul (call $line_glow (call $mod1 (f32.add (f32.mul (f32.sub (local.get $fx) (local.get $cx))
                                                                      (local.get $kx))
                                                             (f32.const 0.37)))
                                        (f32.mul (f32.mul (local.get $wPx) (local.get $kx)) (f32.const 0.5)))
                       (f32.div (f32.div (f32.mul (f32.const 2) (local.get $lwX)) (local.get $kx)) (local.get $wPx)))
              (local.get $fadeX)))
          (local.set $line (select (local.get $lineZ) (local.get $lineX)
                                   (f32.gt (local.get $lineZ) (local.get $lineX))))
          (local.set $r (f32.add (f32.sub (local.get $floorR) (f32.mul (f32.const 0.55) (local.get $lineZ)))
                                 (f32.mul (f32.const 0.55) (local.get $line))))
          (local.set $g (f32.add (f32.sub (local.get $floorG) (f32.mul (f32.const 0.35) (local.get $lineZ)))
                                 (f32.mul (f32.const 0.35) (local.get $line))))
          (local.set $b (f32.add (f32.sub (local.get $floorB) (f32.mul (f32.const 0.75) (local.get $lineZ)))
                                 (f32.mul (f32.const 0.75) (local.get $line))))))
      (i32.store (local.get $px)
        (call $rgb (f64.promote_f32 (local.get $r)) (f64.promote_f32 (local.get $g)) (f64.promote_f32 (local.get $b))))
      (local.set $px (i32.add (local.get $px) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    ;; @end
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H)))))
