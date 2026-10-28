;; FINALE: the closing card, the language's name in chrome over a pool of light
;;
;; The strings are data segments: plain ASCII, readable in the source. The
;; layout is Go's Resize with no HUD (PanelBottom nil), all integer
;; arithmetic; i32.div_s truncates toward zero exactly as Go's / on ints.
;; Memory: strings at 0x14400, 260 background stars (x, y, brightness f32)
;; at 0x14800, the letters' wave offsets (i32) at 0x15800, and the glow's
;; per-column distances (w f32) in SCRATCH.

(data (i32.const 0x14400) "WAT")                              ;; the name
(global $NAME_LEN i32 (i32.const 3))
(data (i32.const 0x14420) "EVERY PIXEL IS WAT")
(global $SUB_LEN i32 (i32.const 18))
(data (i32.const 0x14440) "0 GPU SHADERS")                    ;; 13
(data (i32.const 0x14460) "0 EXTERNAL MODULES")               ;; 18
(data (i32.const 0x14480) "0 ASSETS ON DISK")                 ;; 16
(data (i32.const 0x144A0) "ONE THREAD - NO GPU - NO SHADER")  ;; 31

(global $fi_logoScale (mut i32) (i32.const 0))
(global $fi_logoX     (mut i32) (i32.const 0))
(global $fi_logoY     (mut i32) (i32.const 0))
(global $fi_textH     (mut i32) (i32.const 0))
(global $fi_reflH     (mut i32) (i32.const 0))
(global $fi_floorY    (mut i32) (i32.const 0))
(global $fi_subScale  (mut i32) (i32.const 0))
(global $fi_subX      (mut i32) (i32.const 0))
(global $fi_subY      (mut i32) (i32.const 0))
(global $fi_statsScale (mut i32) (i32.const 0))
(global $fi_statsY    (mut i32) (i32.const 0))
(global $fi_statGap   (mut i32) (i32.const 0))
(global $fi_tagScale  (mut i32) (i32.const 0))
(global $fi_tagX      (mut i32) (i32.const 0))
(global $fi_tagY      (mut i32) (i32.const 0))
(global $fi_glowY     (mut f32) (f32.const 0))
(global $fi_glowR     (mut f32) (f32.const 0))
(global $fi_boxX0 (mut i32) (i32.const 0))
(global $fi_boxX1 (mut i32) (i32.const 0))
(global $fi_boxY0 (mut i32) (i32.const 0))
(global $fi_boxY1 (mut i32) (i32.const 0))

(func $max1 (param $v i32) (result i32)
  (select (i32.const 1) (local.get $v) (i32.lt_s (local.get $v) (i32.const 1))))

(func $finale_start
  (local $w i32) (local $h i32) (local $p i32) (local $x i32)
  (local $subH i32) (local $tagH i32) (local $gap i32) (local $top i32) (local $bottom i32)
  (local $fixed i32) (local $lim i32) (local $logoW i32) (local $blockH i32) (local $y0 i32)
  (local $glowX f32) (local $d f32)
  (local.set $w (global.get $W))
  (local.set $h (global.get $H))
  ;; the background stars: three draws each, x, y, brightness
  (global.set $rng (i32.const 0xF1A1E))
  (local.set $p (i32.const 0x14800))
  (loop $stars
    (f32.store (local.get $p) (call $rng_float32))
    (f32.store offset=4 (local.get $p) (call $rng_float32))
    (f32.store offset=8 (local.get $p)
               (f32.add (f32.const 0.15) (f32.mul (call $rng_float32) (f32.const 0.85))))
    (local.set $p (i32.add (local.get $p) (i32.const 12)))
    (br_if $stars (i32.lt_u (local.get $p) (i32.const 0x15430))))        ;; 260 * 12

  (global.set $fi_subScale (call $max1 (i32.div_s (local.get $w) (i32.const 300))))
  (local.set $subH (i32.mul (i32.const 7) (global.get $fi_subScale)))
  (global.set $fi_statsScale (call $max1 (i32.div_s (local.get $w) (i32.const 440))))
  (global.set $fi_statGap (i32.div_s (i32.mul (i32.mul (i32.const 7) (global.get $fi_statsScale)) (i32.const 3))
                                     (i32.const 2)))
  (global.set $fi_tagScale (i32.add (global.get $fi_statsScale) (i32.const 1)))
  (local.set $tagH (i32.mul (i32.const 7) (global.get $fi_tagScale)))
  (local.set $gap (i32.div_s (local.get $h) (i32.const 48)))
  (local.set $top (i32.div_s (local.get $h) (i32.const 40)))            ;; no HUD panel above
  (local.set $bottom (i32.trunc_f32_s (f32.mul (f32.convert_i32_s (local.get $h)) (f32.const 0.90))))
  (local.set $fixed (i32.add (i32.add (local.get $subH) (i32.mul (i32.const 3) (global.get $fi_statGap)))
                             (i32.add (local.get $tagH) (i32.mul (i32.const 4) (local.get $gap)))))
  ;; the name's scale: 10.5 blocks of height (glyph plus half a reflection),
  ;; and never wider than 45% of the frame
  (global.set $fi_logoScale (i32.div_s (i32.mul (i32.sub (i32.sub (local.get $bottom) (local.get $top))
                                                         (local.get $fixed))
                                                (i32.const 2))
                                       (i32.const 21)))
  (local.set $lim (i32.div_s (i32.div_s (i32.mul (local.get $w) (i32.const 9)) (i32.const 20))
                             (call $text_width (global.get $NAME_LEN) (i32.const 1))))
  (if (i32.gt_s (global.get $fi_logoScale) (local.get $lim))
    (then (global.set $fi_logoScale (local.get $lim))))
  (if (i32.lt_s (global.get $fi_logoScale) (i32.const 3))
    (then (global.set $fi_logoScale (i32.const 3))))
  (local.set $logoW (call $text_width (global.get $NAME_LEN) (global.get $fi_logoScale)))
  (global.set $fi_textH (i32.mul (i32.const 7) (global.get $fi_logoScale)))
  (global.set $fi_reflH (i32.div_s (global.get $fi_textH) (i32.const 2)))
  (global.set $fi_logoX (i32.div_s (i32.sub (local.get $w) (local.get $logoW)) (i32.const 2)))
  (local.set $blockH (i32.add (i32.add (global.get $fi_textH) (global.get $fi_reflH)) (local.get $fixed)))
  (local.set $y0 (i32.add (local.get $top)
                          (i32.div_s (i32.sub (i32.sub (local.get $bottom) (local.get $top)) (local.get $blockH))
                                     (i32.const 2))))
  (global.set $fi_logoY (local.get $y0))
  (global.set $fi_floorY (i32.add (global.get $fi_logoY) (global.get $fi_textH)))
  (global.set $fi_subY (i32.add (i32.add (global.get $fi_floorY) (global.get $fi_reflH)) (local.get $gap)))
  (global.set $fi_statsY (i32.add (i32.add (global.get $fi_subY) (local.get $subH)) (local.get $gap)))
  (global.set $fi_tagY (i32.add (i32.add (global.get $fi_statsY) (i32.mul (i32.const 3) (global.get $fi_statGap)))
                                (local.get $gap)))
  (global.set $fi_subX (i32.div_s (i32.sub (local.get $w)
                                           (call $text_width (global.get $SUB_LEN) (global.get $fi_subScale)))
                                  (i32.const 2)))
  (global.set $fi_tagX (i32.div_s (i32.sub (local.get $w) (call $text_width (i32.const 31) (global.get $fi_tagScale)))
                                  (i32.const 2)))
  ;; the glow: an ellipse 1.6x wider than tall, and the box it can reach
  (local.set $glowX (f32.mul (f32.convert_i32_s (local.get $w)) (f32.const 0.5)))
  (global.set $fi_glowY (f32.add (f32.convert_i32_s (global.get $fi_logoY))
                                 (f32.mul (f32.convert_i32_s (global.get $fi_textH)) (f32.const 0.55))))
  (global.set $fi_glowR (f32.mul (f32.convert_i32_s (local.get $w)) (f32.const 0.34)))
  (loop $cols
    (local.set $d (f32.mul (f32.div (f32.sub (f32.convert_i32_s (local.get $x)) (local.get $glowX))
                                    (global.get $fi_glowR))
                           (f32.const 1.6)))
    (f32.store (i32.add (global.get $SCRATCH) (i32.shl (local.get $x) (i32.const 2)))
               (f32.mul (local.get $d) (local.get $d)))
    (local.set $x (i32.add (local.get $x) (i32.const 1)))
    (br_if $cols (i32.lt_s (local.get $x) (local.get $w))))
  (global.set $fi_boxX0 (i32.sub (i32.trunc_f32_s (local.get $glowX))
                                 (i32.trunc_f32_s (f32.div (global.get $fi_glowR) (f32.const 1.6)))))
  (global.set $fi_boxX1 (i32.add (i32.trunc_f32_s (local.get $glowX))
                                 (i32.trunc_f32_s (f32.div (global.get $fi_glowR) (f32.const 1.6)))))
  (global.set $fi_boxY0 (i32.sub (i32.trunc_f32_s (global.get $fi_glowY)) (i32.trunc_f32_s (global.get $fi_glowR))))
  (global.set $fi_boxY1 (i32.add (i32.trunc_f32_s (global.get $fi_glowY)) (i32.trunc_f32_s (global.get $fi_glowR)))))

(func $finale_render (param $t f64)
  (local $w i32) (local $h i32) (local $x i32) (local $y i32) (local $i i32) (local $a i32)
  (local $row i32) (local $end i32) (local $p i32) (local $c i32)
  (local $fy f32) (local $invH f32) (local $u f32) (local $ny f32) (local $vig f32) (local $cy f32) (local $cx f32)
  (local $by0 i32) (local $by1 i32) (local $bx0 i32) (local $bx1 i32)
  (local $pulse f32) (local $dy f32) (local $dy2 f32) (local $d2 f32) (local $g f32)
  (local $tw f32) (local $sx i32) (local $sy i32)
  (local $d f32) (local $fade f32) (local $glow f32)
  (local $scale i32) (local $subW i32) (local $lineLen i32) (local $ly i32) (local $lw i32)
  (local.set $w (global.get $W))
  (local.set $h (global.get $H))
  (local.set $cx (f32.mul (f32.convert_i32_s (local.get $w)) (f32.const 0.5)))
  (local.set $cy (f32.mul (f32.convert_i32_s (local.get $h)) (f32.const 0.5)))

  ;; background, pass 1: one colour per row, a vertical ramp with a vignette
  (local.set $invH (f32.div (f32.const 1) (f32.convert_i32_s (local.get $h))))
  (loop $rows
    (local.set $fy (f32.convert_i32_s (local.get $y)))
    (local.set $ny (f32.div (f32.sub (local.get $fy) (local.get $cy)) (local.get $cy)))
    (local.set $vig (f32.max (f32.sub (f32.const 1) (f32.mul (f32.mul (f32.const 0.32) (local.get $ny)) (local.get $ny)))
                             (f32.const 0.45)))
    (local.set $u (f32.mul (local.get $fy) (local.get $invH)))
    (local.set $c (call $rgb
      (f64.promote_f32 (f32.mul (f32.add (f32.const 0.02) (f32.mul (f32.mul (f32.const 0.09) (local.get $u)) (local.get $u)))
                                (local.get $vig)))
      (f64.promote_f32 (f32.mul (f32.add (f32.const 0.01) (f32.mul (f32.const 0.02) (local.get $u))) (local.get $vig)))
      (f64.promote_f32 (f32.mul (f32.add (f32.const 0.06) (f32.mul (f32.const 0.14) (local.get $u))) (local.get $vig)))))
    (local.set $p (i32.add (i32.const 0x120000) (i32.shl (i32.mul (local.get $y) (local.get $w)) (i32.const 2))))
    (local.set $end (i32.add (local.get $p) (i32.shl (local.get $w) (i32.const 2))))
    (loop $fill
      (i32.store (local.get $p) (local.get $c))
      (local.set $p (i32.add (local.get $p) (i32.const 4)))
      (br_if $fill (i32.lt_u (local.get $p) (local.get $end))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (local.get $h))))

  ;; background, pass 2: the pool of light, only inside its box
  (local.set $by0 (select (i32.const 0) (global.get $fi_boxY0) (i32.lt_s (global.get $fi_boxY0) (i32.const 0))))
  (local.set $by1 (select (local.get $h) (global.get $fi_boxY1) (i32.gt_s (global.get $fi_boxY1) (local.get $h))))
  (local.set $bx0 (select (i32.const 0) (global.get $fi_boxX0) (i32.lt_s (global.get $fi_boxX0) (i32.const 0))))
  (local.set $bx1 (select (local.get $w) (global.get $fi_boxX1) (i32.gt_s (global.get $fi_boxX1) (local.get $w))))
  (local.set $pulse (f32.add (f32.const 0.88)
                             (f32.mul (f32.const 0.12)
                                      (f32.demote_f64 (call $sin64 (f64.mul (local.get $t) (f64.const 2.2)))))))
  (local.set $y (local.get $by0))
  (block $glowDone
    (loop $grows
      (br_if $glowDone (i32.ge_s (local.get $y) (local.get $by1)))
      (local.set $dy (f32.div (f32.sub (f32.convert_i32_s (local.get $y)) (global.get $fi_glowY)) (global.get $fi_glowR)))
      (local.set $dy2 (f32.mul (local.get $dy) (local.get $dy)))
      (if (f32.lt (local.get $dy2) (f32.const 1))
        (then
          (local.set $x (local.get $bx0))
          (block $rowDone
            (loop $gcols
              (br_if $rowDone (i32.ge_s (local.get $x) (local.get $bx1)))
              (local.set $d2 (f32.add (f32.load (i32.add (global.get $SCRATCH) (i32.shl (local.get $x) (i32.const 2))))
                                      (local.get $dy2)))
              (if (f32.lt (local.get $d2) (f32.const 1))
                (then
                  (local.set $g (f32.sub (f32.const 1) (local.get $d2)))
                  (local.set $g (f32.mul (local.get $g) (f32.mul (local.get $g) (local.get $pulse))))
                  (local.set $a (i32.add (i32.const 0x120000)
                                         (i32.shl (i32.add (i32.mul (local.get $y) (local.get $w)) (local.get $x))
                                                  (i32.const 2))))
                  (local.set $p (i32.load (local.get $a)))
                  (i32.store (local.get $a)
                    (call $pack_sat
                      (i32.add (call $ch (local.get $p) (i32.const 0))
                               (i32.trunc_f32_s (f32.mul (local.get $g) (f32.const 120))))
                      (i32.add (call $ch (local.get $p) (i32.const 1))
                               (i32.trunc_f32_s (f32.mul (local.get $g) (f32.const 22))))
                      (i32.add (call $ch (local.get $p) (i32.const 2))
                               (i32.trunc_f32_s (f32.mul (local.get $g) (f32.const 100))))))))
              (local.set $x (i32.add (local.get $x) (i32.const 1)))
              (br $gcols)))))
      (local.set $y (i32.add (local.get $y) (i32.const 1)))
      (br $grows)))

  ;; the stars, twinkling slowly: one sine per star, in f64 like Go's math.Sin
  (local.set $i (i32.const 0))
  (loop $stars
    (local.set $p (i32.add (i32.const 0x14800) (i32.mul (local.get $i) (i32.const 12))))
    (local.set $sx (i32.trunc_f32_s (f32.mul (f32.load (local.get $p)) (f32.convert_i32_s (local.get $w)))))
    (local.set $sy (i32.trunc_f32_s (f32.mul (f32.load offset=4 (local.get $p)) (f32.convert_i32_s (local.get $h)))))
    (if (i32.and (i32.lt_u (local.get $sx) (local.get $w)) (i32.lt_u (local.get $sy) (local.get $h)))
      (then
        (local.set $tw (f32.add (f32.const 0.55)
          (f32.mul (f32.const 0.45)
                   (f32.demote_f64 (call $sin64 (f64.add (f64.mul (local.get $t) (f64.const 1.7))
                                                         (f64.mul (f64.convert_i32_s (local.get $i)) (f64.const 0.7))))))))
        (call $additive (i32.add (i32.mul (local.get $sy) (local.get $w)) (local.get $sx))
                        (i32.const 0xFF40306A)
                        (i32.trunc_f32_u (f32.mul (f32.mul (f32.const 70) (f32.load offset=8 (local.get $p)))
                                                  (local.get $tw))))))
    (local.set $i (i32.add (local.get $i) (i32.const 1)))
    (br_if $stars (i32.lt_u (local.get $i) (i32.const 260))))

  ;; the polished floor line the reflection lands on
  (if (i32.lt_u (global.get $fi_floorY) (local.get $h))
    (then
      (local.set $x (i32.const 0))
      (loop $floor
        (local.set $d (f32.sub (f32.convert_i32_s (local.get $x)) (local.get $cx)))
        (local.set $fade (f32.sub (f32.const 1)
                                  (f32.div (f32.abs (local.get $d))
                                           (f32.mul (f32.convert_i32_s (local.get $w)) (f32.const 0.52)))))
        (if (f32.gt (local.get $fade) (f32.const 0))
          (then
            (local.set $glow (f32.mul (f32.mul (local.get $fade) (local.get $fade)) (f32.const 0.9)))
            (local.set $a (i32.add (i32.const 0x120000)
                                   (i32.shl (i32.add (i32.mul (global.get $fi_floorY) (local.get $w)) (local.get $x))
                                            (i32.const 2))))
            (local.set $p (i32.load (local.get $a)))
            ;; float sums clamped at 255, then truncated
            (i32.store (local.get $a)
              (call $pack_sat
                (i32.trunc_f32_u (f32.min (f32.add (f32.convert_i32_u (call $ch (local.get $p) (i32.const 0)))
                                                   (f32.mul (f32.const 210) (local.get $glow))) (f32.const 255)))
                (i32.trunc_f32_u (f32.min (f32.add (f32.convert_i32_u (call $ch (local.get $p) (i32.const 1)))
                                                   (f32.mul (f32.const 110) (local.get $glow))) (f32.const 255)))
                (i32.trunc_f32_u (f32.min (f32.add (f32.convert_i32_u (call $ch (local.get $p) (i32.const 2)))
                                                   (f32.mul (f32.const 230) (local.get $glow))) (f32.const 255)))))))
        (local.set $x (i32.add (local.get $x) (i32.const 1)))
        (br_if $floor (i32.lt_s (local.get $x) (local.get $w))))))

  ;; @excerpt FINALE
  ;; the logo: the letters bounce off the floor line, offsets from
  ;; -scale/3 (up) to 0 (resting), truncated toward zero by trunc_f64_s
  (local.set $scale (global.get $fi_logoScale))
  (local.set $i (i32.const 0))
  (loop $offs
    (i32.store offset=0x15800 (i32.shl (local.get $i) (i32.const 2))
      (i32.trunc_f64_s
        (f64.div (f64.mul (f64.sub (call $sin64 (f64.add (f64.mul (local.get $t) (f64.const 2.4))
                                                         (f64.mul (f64.convert_i32_s (local.get $i)) (f64.const 0.75))))
                                   (f64.const 1))
                          (f64.convert_i32_s (local.get $scale)))
                 (f64.const 6))))
    (local.set $i (i32.add (local.get $i) (i32.const 1)))
    (br_if $offs (i32.lt_u (local.get $i) (global.get $NAME_LEN))))
  ;; reflection first, so the name sits on its own light; then a one-pixel
  ;; dark edge; then the chrome: cream, rose, violet
  (call $draw_text_reflect (global.get $fi_logoX) (global.get $fi_floorY) (i32.const 0x14400) (global.get $NAME_LEN)
        (local.get $scale) (i32.const 0xFFFFF6E8) (i32.const 0xFF582080) (i32.const 0x15800)
        (i32.const 125) (global.get $fi_reflH))
  (call $draw_text_outline (global.get $fi_logoX) (global.get $fi_logoY) (i32.const 0x14400) (global.get $NAME_LEN)
        (local.get $scale) (i32.const 0xFF200A18) (i32.const 0x15800))
  (call $draw_text_gradient (global.get $fi_logoX) (global.get $fi_logoY) (i32.const 0x14400) (global.get $NAME_LEN)
        (local.get $scale) (i32.const 0xFFFFF6E8) (i32.const 0xFF7C9CFF) (i32.const 0xFF582080) (i32.const 0x15800))
  ;; @end

  ;; the subtitle with a rule either side
  (local.set $subW (call $text_width (global.get $SUB_LEN) (global.get $fi_subScale)))
  (local.set $lineLen (i32.div_s (local.get $subW) (i32.const 3)))
  (local.set $ly (i32.add (global.get $fi_subY) (i32.div_s (i32.mul (i32.const 7) (global.get $fi_subScale)) (i32.const 2))))
  (call $hline (i32.sub (i32.sub (global.get $fi_subX) (local.get $lineLen)) (i32.const 14))
               (local.get $ly) (local.get $lineLen) (i32.const 0xFF9050A0))
  (call $hline (i32.add (i32.add (global.get $fi_subX) (local.get $subW)) (i32.const 14))
               (local.get $ly) (local.get $lineLen) (i32.const 0xFF9050A0))
  (call $draw_text (global.get $fi_subX) (global.get $fi_subY) (i32.const 0x14420) (global.get $SUB_LEN)
                   (global.get $fi_subScale) (i32.const 0xFFF0E0FF))
  ;; the closing numbers, centred, then the punchline
  (call $finale_line (i32.const 0x14440) (i32.const 13) (i32.const 0))
  (call $finale_line (i32.const 0x14460) (i32.const 18) (i32.const 1))
  (call $finale_line (i32.const 0x14480) (i32.const 16) (i32.const 2))
  (call $draw_text (global.get $fi_tagX) (global.get $fi_tagY) (i32.const 0x144A0) (i32.const 31)
                   (global.get $fi_tagScale) (i32.const 0xFFB0E0FF)))

(func $finale_line (param $s i32) (param $len i32) (param $n i32)
  (call $draw_text
    (i32.div_s (i32.sub (global.get $W) (call $text_width (local.get $len) (global.get $fi_statsScale)))
               (i32.const 2))
    (i32.add (global.get $fi_statsY) (i32.mul (local.get $n) (global.get $fi_statGap)))
    (local.get $s) (local.get $len) (global.get $fi_statsScale) (i32.const 0xFFC0B0E0)))
