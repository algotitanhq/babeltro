;; text: drawing with the 5x7 font (font.wat), Go's canvas text helpers
;;
;; A string is a (pointer, length) pair of ASCII bytes in memory; the
;; finale's strings are data segments in finale.wat. Every glyph is 5 pixels
;; wide plus a 1-pixel gap, times the integer scale.

;; text_width: (6*len - 1) * scale, canvas.TextWidth
(func $text_width (param $len i32) (param $scale i32) (result i32)
  (if (result i32) (i32.eqz (local.get $len))
    (then (i32.const 0))
    (else (i32.mul (i32.sub (i32.mul (local.get $len) (i32.const 6)) (i32.const 1))
                   (local.get $scale)))))

;; glyph: the font address of byte ch, or -1 outside ASCII 32..126
;; (lowercase folds to uppercase, as Go's glyphIndex does)
(func $glyph (param $ch i32) (result i32)
  (if (i32.and (i32.ge_u (local.get $ch) (i32.const 97)) (i32.le_u (local.get $ch) (i32.const 122)))
    (then (local.set $ch (i32.sub (local.get $ch) (i32.const 32)))))
  (local.set $ch (i32.sub (local.get $ch) (i32.const 32)))
  (if (result i32) (i32.lt_u (local.get $ch) (i32.const 95))   ;; unsigned: negatives fail too
    (then (i32.add (i32.const 0x14000) (i32.shl (local.get $ch) (i32.const 3))))
    (else (i32.const -1))))

;; additive adds colour c scaled by inten/255 to pixel i, saturating
(func $additive (param $i i32) (param $c i32) (param $inten i32)
  (local $a i32) (local $p i32) (local $r i32) (local $g i32) (local $b i32)
  (if (i32.eqz (local.get $inten)) (then (return)))
  (local.set $a (i32.add (i32.const 0x120000) (i32.shl (local.get $i) (i32.const 2))))
  (local.set $p (i32.load (local.get $a)))
  (local.set $r (i32.add (i32.and (local.get $p) (i32.const 0xFF))
                         (i32.div_u (i32.mul (i32.and (local.get $c) (i32.const 0xFF)) (local.get $inten))
                                    (i32.const 255))))
  (local.set $g (i32.add (i32.and (i32.shr_u (local.get $p) (i32.const 8)) (i32.const 0xFF))
                         (i32.div_u (i32.mul (i32.and (i32.shr_u (local.get $c) (i32.const 8)) (i32.const 0xFF))
                                             (local.get $inten))
                                    (i32.const 255))))
  (local.set $b (i32.add (i32.and (i32.shr_u (local.get $p) (i32.const 16)) (i32.const 0xFF))
                         (i32.div_u (i32.mul (i32.and (i32.shr_u (local.get $c) (i32.const 16)) (i32.const 0xFF))
                                             (local.get $inten))
                                    (i32.const 255))))
  (i32.store (local.get $a) (call $pack_sat (local.get $r) (local.get $g) (local.get $b))))

;; pack_sat: 0xFFBBGGRR from channels, each clamped to 255 (never negative)
(func $pack_sat (param $r i32) (param $g i32) (param $b i32) (result i32)
  (i32.or
    (i32.or (i32.const 0xFF000000)
            (i32.shl (select (i32.const 255) (local.get $b) (i32.gt_s (local.get $b) (i32.const 255)))
                     (i32.const 16)))
    (i32.or (i32.shl (select (i32.const 255) (local.get $g) (i32.gt_s (local.get $g) (i32.const 255)))
                     (i32.const 8))
            (select (i32.const 255) (local.get $r) (i32.gt_s (local.get $r) (i32.const 255))))))

;; hline: a 1-pixel horizontal line, clipped
(func $hline (param $x i32) (param $y i32) (param $w i32) (param $c i32)
  (local $xx i32) (local $end i32)
  (if (i32.ge_u (local.get $y) (global.get $H)) (then (return)))   ;; also y < 0
  (local.set $xx (local.get $x))
  (local.set $end (i32.add (local.get $x) (local.get $w)))
  (block $done
    (loop $each
      (br_if $done (i32.ge_s (local.get $xx) (local.get $end)))
      (if (i32.lt_u (local.get $xx) (global.get $W))
        (then (i32.store offset=0x120000
                (i32.shl (i32.add (i32.mul (local.get $y) (global.get $W)) (local.get $xx)) (i32.const 2))
                (local.get $c))))
      (local.set $xx (i32.add (local.get $xx) (i32.const 1)))
      (br $each))))

;; draw_text: solid text, clipped per pixel (DrawText, alpha 255). The bounds
;; tests use one unsigned compare each: a negative coordinate, seen as
;; unsigned, is a huge number, so `xx <u W` means 0 <= xx < W.
(func $draw_text (param $x i32) (param $y i32) (param $s i32) (param $len i32)
                 (param $scale i32) (param $c i32)
  (local $g i32) (local $row i32) (local $col i32) (local $bits i32)
  (local $px i32) (local $py i32) (local $sx i32) (local $sy i32) (local $xx i32) (local $yy i32)
  (local $end i32)
  (local.set $end (i32.add (local.get $s) (local.get $len)))
  (block $done
    (loop $chars
      (br_if $done (i32.ge_u (local.get $s) (local.get $end)))
      (local.set $g (call $glyph (i32.load8_u (local.get $s))))
      (if (i32.ge_s (local.get $g) (i32.const 0))
        (then
          (local.set $row (i32.const 0))
          (loop $rows
            (local.set $bits (i32.load8_u (i32.add (local.get $g) (local.get $row))))
            (local.set $col (i32.const 0))
            (loop $cols
              (if (i32.and (local.get $bits) (i32.shr_u (i32.const 16) (local.get $col)))
                (then
                  (local.set $px (i32.add (local.get $x) (i32.mul (local.get $col) (local.get $scale))))
                  (local.set $py (i32.add (local.get $y) (i32.mul (local.get $row) (local.get $scale))))
                  (local.set $sy (i32.const 0))
                  (loop $by
                    (local.set $yy (i32.add (local.get $py) (local.get $sy)))
                    (if (i32.lt_u (local.get $yy) (global.get $H))
                      (then
                        (local.set $sx (i32.const 0))
                        (loop $bx
                          (local.set $xx (i32.add (local.get $px) (local.get $sx)))
                          (if (i32.lt_u (local.get $xx) (global.get $W))
                            (then (i32.store offset=0x120000
                                    (i32.shl (i32.add (i32.mul (local.get $yy) (global.get $W))
                                                      (local.get $xx))
                                             (i32.const 2))
                                    (local.get $c))))
                          (local.set $sx (i32.add (local.get $sx) (i32.const 1)))
                          (br_if $bx (i32.lt_s (local.get $sx) (local.get $scale))))))
                    (local.set $sy (i32.add (local.get $sy) (i32.const 1)))
                    (br_if $by (i32.lt_s (local.get $sy) (local.get $scale))))))
              (local.set $col (i32.add (local.get $col) (i32.const 1)))
              (br_if $cols (i32.lt_u (local.get $col) (i32.const 5))))
            (local.set $row (i32.add (local.get $row) (i32.const 1)))
            (br_if $rows (i32.lt_u (local.get $row) (i32.const 7)))))
        (else (local.set $x (i32.sub (local.get $x) (local.get $scale)))))  ;; unknown: 5, not 6
      (local.set $x (i32.add (local.get $x) (i32.mul (i32.const 6) (local.get $scale))))
      (local.set $s (i32.add (local.get $s) (i32.const 1)))
      (br $chars))))

;; clip: the visible part of the scale x scale block at (px, py), as four
;; results y0 y1 x0 x1 (multi-value again); empty when y0 >= y1 or x0 >= x1
(func $clip (param $px i32) (param $py i32) (param $scale i32) (result i32 i32 i32 i32)
  (local $y1 i32) (local $x1 i32)
  (local.set $y1 (i32.add (local.get $py) (local.get $scale)))
  (local.set $x1 (i32.add (local.get $px) (local.get $scale)))
  (select (i32.const 0) (local.get $py) (i32.lt_s (local.get $py) (i32.const 0)))
  (select (global.get $H) (local.get $y1) (i32.gt_s (local.get $y1) (global.get $H)))
  (select (i32.const 0) (local.get $px) (i32.lt_s (local.get $px) (i32.const 0)))
  (select (global.get $W) (local.get $x1) (i32.gt_s (local.get $x1) (global.get $W))))

;; lerp_ch: uint32(float32(a) + (float32(b) - float32(a))*u), for one channel
(func $lerp_ch (param $a i32) (param $b i32) (param $u f32) (result i32)
  (i32.trunc_f32_u
    (f32.add (f32.convert_i32_u (local.get $a))
             (f32.mul (f32.sub (f32.convert_i32_u (local.get $b)) (f32.convert_i32_u (local.get $a)))
                      (local.get $u)))))

;; channel n (0 red, 1 green, 2 blue) of a packed colour
(func $ch (param $c i32) (param $n i32) (result i32)
  (i32.and (i32.shr_u (local.get $c) (i32.shl (local.get $n) (i32.const 3))) (i32.const 0xFF)))

;; draw_text_gradient: DrawTextGradient, a three-stop vertical ramp with
;; scanlines (every fourth row at 3/4), each letter at its own offset from
;; the i32 array at $offs
(func $draw_text_gradient (param $x i32) (param $y i32) (param $s i32) (param $len i32)
                          (param $scale i32) (param $top i32) (param $mid i32) (param $bot i32)
                          (param $offs i32)
  (local $i i32) (local $g i32) (local $dy i32) (local $row i32) (local $col i32) (local $bits i32)
  (local $px i32) (local $py i32) (local $cy0 i32) (local $cy1 i32) (local $cx0 i32) (local $cx1 i32)
  (local $yy i32) (local $xx i32) (local $f f32) (local $u f32) (local $c i32)
  (local $r i32) (local $gg i32) (local $bl i32) (local $totalH f32)
  (local.set $totalH (f32.convert_i32_s (i32.mul (i32.const 7) (local.get $scale))))
  (block $done
    (loop $chars
      (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
      (local.set $dy (i32.load (i32.add (local.get $offs) (i32.shl (local.get $i) (i32.const 2)))))
      (local.set $g (call $glyph (i32.load8_u (i32.add (local.get $s) (local.get $i)))))
      (if (i32.ge_s (local.get $g) (i32.const 0))
        (then
          (local.set $row (i32.const 0))
          (loop $rows
            (local.set $bits (i32.load8_u (i32.add (local.get $g) (local.get $row))))
            (local.set $py (i32.add (i32.add (local.get $y) (i32.mul (local.get $row) (local.get $scale)))
                                    (local.get $dy)))
            (local.set $col (i32.const 0))
            (loop $cols
              (if (i32.and (local.get $bits) (i32.shr_u (i32.const 16) (local.get $col)))
                (then
                  (local.set $px (i32.add (local.get $x) (i32.mul (local.get $col) (local.get $scale))))
                  (call $clip (local.get $px) (local.get $py) (local.get $scale))
                  (local.set $cx1) (local.set $cx0) (local.set $cy1) (local.set $cy0)
                  (if (i32.and (i32.lt_s (local.get $cy0) (local.get $cy1))
                               (i32.lt_s (local.get $cx0) (local.get $cx1)))
                    (then
                      (local.set $yy (local.get $cy0))
                      (loop $by
                        (local.set $f (f32.div (f32.convert_i32_s (i32.sub (local.get $yy) (local.get $y)))
                                               (local.get $totalH)))
                        (local.set $f (f32.min (f32.max (local.get $f) (f32.const 0)) (f32.const 1)))
                        (if (f32.lt (local.get $f) (f32.const 0.5))
                          (then
                            (local.set $u (f32.mul (local.get $f) (f32.const 2)))
                            (local.set $r  (call $lerp_ch (call $ch (local.get $top) (i32.const 0))
                                                          (call $ch (local.get $mid) (i32.const 0)) (local.get $u)))
                            (local.set $gg (call $lerp_ch (call $ch (local.get $top) (i32.const 1))
                                                          (call $ch (local.get $mid) (i32.const 1)) (local.get $u)))
                            (local.set $bl (call $lerp_ch (call $ch (local.get $top) (i32.const 2))
                                                          (call $ch (local.get $mid) (i32.const 2)) (local.get $u))))
                          (else
                            (local.set $u (f32.mul (f32.sub (local.get $f) (f32.const 0.5)) (f32.const 2)))
                            (local.set $r  (call $lerp_ch (call $ch (local.get $mid) (i32.const 0))
                                                          (call $ch (local.get $bot) (i32.const 0)) (local.get $u)))
                            (local.set $gg (call $lerp_ch (call $ch (local.get $mid) (i32.const 1))
                                                          (call $ch (local.get $bot) (i32.const 1)) (local.get $u)))
                            (local.set $bl (call $lerp_ch (call $ch (local.get $mid) (i32.const 2))
                                                          (call $ch (local.get $bot) (i32.const 2)) (local.get $u)))))
                        ;; the scanline: every fourth screen row at 3/4
                        (if (i32.eqz (i32.and (local.get $yy) (i32.const 3)))
                          (then
                            (local.set $r  (i32.div_u (i32.mul (local.get $r)  (i32.const 3)) (i32.const 4)))
                            (local.set $gg (i32.div_u (i32.mul (local.get $gg) (i32.const 3)) (i32.const 4)))
                            (local.set $bl (i32.div_u (i32.mul (local.get $bl) (i32.const 3)) (i32.const 4)))))
                        (local.set $c (call $pack_sat (local.get $r) (local.get $gg) (local.get $bl)))
                        (local.set $xx (local.get $cx0))
                        (loop $bx
                          (i32.store offset=0x120000
                            (i32.shl (i32.add (i32.mul (local.get $yy) (global.get $W)) (local.get $xx))
                                     (i32.const 2))
                            (local.get $c))
                          (local.set $xx (i32.add (local.get $xx) (i32.const 1)))
                          (br_if $bx (i32.lt_s (local.get $xx) (local.get $cx1))))
                        (local.set $yy (i32.add (local.get $yy) (i32.const 1)))
                        (br_if $by (i32.lt_s (local.get $yy) (local.get $cy1))))))))
              (local.set $col (i32.add (local.get $col) (i32.const 1)))
              (br_if $cols (i32.lt_u (local.get $col) (i32.const 5))))
            (local.set $row (i32.add (local.get $row) (i32.const 1)))
            (br_if $rows (i32.lt_u (local.get $row) (i32.const 7))))))
      (local.set $x (i32.add (local.get $x) (i32.mul (i32.const 6) (local.get $scale))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $chars))))

;; draw_text_outline: each letter drawn four times, one pixel left, right,
;; up and down, in a dark colour (DrawTextOutline)
(func $draw_text_outline (param $x i32) (param $y i32) (param $s i32) (param $len i32)
                         (param $scale i32) (param $c i32) (param $offs i32)
  (local $i i32) (local $gx i32) (local $gy i32) (local $ch i32)
  (block $done
    (loop $chars
      (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
      (local.set $ch (i32.add (local.get $s) (local.get $i)))
      (local.set $gx (i32.add (local.get $x) (i32.mul (i32.mul (local.get $i) (i32.const 6)) (local.get $scale))))
      (local.set $gy (i32.add (local.get $y)
                              (i32.load (i32.add (local.get $offs) (i32.shl (local.get $i) (i32.const 2))))))
      (call $draw_text (i32.sub (local.get $gx) (i32.const 1)) (local.get $gy) (local.get $ch) (i32.const 1) (local.get $scale) (local.get $c))
      (call $draw_text (i32.add (local.get $gx) (i32.const 1)) (local.get $gy) (local.get $ch) (i32.const 1) (local.get $scale) (local.get $c))
      (call $draw_text (local.get $gx) (i32.sub (local.get $gy) (i32.const 1)) (local.get $ch) (i32.const 1) (local.get $scale) (local.get $c))
      (call $draw_text (local.get $gx) (i32.add (local.get $gy) (i32.const 1)) (local.get $ch) (i32.const 1) (local.get $scale) (local.get $c))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $chars))))

;; draw_text_reflect: the letters mirrored below the line y, fading over
;; depth rows, added to the frame like light on a polished floor
(func $draw_text_reflect (param $x i32) (param $y i32) (param $s i32) (param $len i32)
                         (param $scale i32) (param $top i32) (param $bot i32) (param $offs i32)
                         (param $strength i32) (param $depth i32)
  (local $i i32) (local $g i32) (local $dy i32) (local $row i32) (local $col i32) (local $bits i32)
  (local $px i32) (local $py i32) (local $cy0 i32) (local $cy1 i32) (local $cx0 i32) (local $cx1 i32)
  (local $yy i32) (local $xx i32) (local $d f32) (local $a f32) (local $inten i32) (local $c i32)
  (if (i32.lt_s (local.get $depth) (i32.const 1)) (then (local.set $depth (i32.const 1))))
  (block $done
    (loop $chars
      (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
      (local.set $dy (i32.load (i32.add (local.get $offs) (i32.shl (local.get $i) (i32.const 2)))))
      (local.set $g (call $glyph (i32.load8_u (i32.add (local.get $s) (local.get $i)))))
      (if (i32.ge_s (local.get $g) (i32.const 0))
        (then
          (local.set $row (i32.const 0))
          (loop $rows
            (local.set $bits (i32.load8_u (i32.add (local.get $g) (local.get $row))))
            ;; mirrored: row 0 lands at the far end, and a letter lifted by
            ;; dy has its reflection pushed down by as much
            (local.set $py (i32.sub (i32.add (local.get $y)
                                             (i32.mul (i32.sub (i32.const 6) (local.get $row)) (local.get $scale)))
                                    (local.get $dy)))
            (local.set $col (i32.const 0))
            (loop $cols
              (if (i32.and (local.get $bits) (i32.shr_u (i32.const 16) (local.get $col)))
                (then
                  (local.set $px (i32.add (local.get $x) (i32.mul (local.get $col) (local.get $scale))))
                  (call $clip (local.get $px) (local.get $py) (local.get $scale))
                  (local.set $cx1) (local.set $cx0) (local.set $cy1) (local.set $cy0)
                  (if (i32.and (i32.lt_s (local.get $cy0) (local.get $cy1))
                               (i32.lt_s (local.get $cx0) (local.get $cx1)))
                    (then
                      (local.set $yy (local.get $cy0))
                      (loop $by
                        (local.set $d (f32.div (f32.convert_i32_s (i32.sub (local.get $yy) (local.get $y)))
                                               (f32.convert_i32_s (local.get $depth))))
                        (if (f32.le (local.get $d) (f32.const 1))
                          (then
                            (local.set $a (f32.sub (f32.const 1) (local.get $d)))
                            (local.set $a (f32.mul (local.get $a) (local.get $a)))
                            (local.set $inten (i32.trunc_f32_u
                                                (f32.mul (f32.convert_i32_u (local.get $strength)) (local.get $a))))
                            (if (local.get $inten)
                              (then
                                (local.set $c (call $pack_sat
                                  (call $lerp_ch (call $ch (local.get $top) (i32.const 0))
                                                 (call $ch (local.get $bot) (i32.const 0)) (local.get $d))
                                  (call $lerp_ch (call $ch (local.get $top) (i32.const 1))
                                                 (call $ch (local.get $bot) (i32.const 1)) (local.get $d))
                                  (call $lerp_ch (call $ch (local.get $top) (i32.const 2))
                                                 (call $ch (local.get $bot) (i32.const 2)) (local.get $d))))
                                (local.set $xx (local.get $cx0))
                                (loop $bx
                                  (call $additive (i32.add (i32.mul (local.get $yy) (global.get $W)) (local.get $xx))
                                                  (local.get $c) (local.get $inten))
                                  (local.set $xx (i32.add (local.get $xx) (i32.const 1)))
                                  (br_if $bx (i32.lt_s (local.get $xx) (local.get $cx1))))))))
                        (local.set $yy (i32.add (local.get $yy) (i32.const 1)))
                        (br_if $by (i32.lt_s (local.get $yy) (local.get $cy1))))))))
              (local.set $col (i32.add (local.get $col) (i32.const 1)))
              (br_if $cols (i32.lt_u (local.get $col) (i32.const 5))))
            (local.set $row (i32.add (local.get $row) (i32.const 1)))
            (br_if $rows (i32.lt_u (local.get $row) (i32.const 7))))))
      (local.set $x (i32.add (local.get $x) (i32.mul (i32.const 6) (local.get $scale))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $chars))))
