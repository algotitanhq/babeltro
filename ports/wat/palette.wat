;; palette: 256-colour ramps, built once at start-up
;;
;; Go's palette.New interpolates a handful of colour stops with a smoothstep.
;; Here the stops are written into memory at 0x100 by $stop, one call per
;; stop, then $build_palette turns them into 256 packed pixels. A data
;; segment of f64 stops would be unreadable bytes; calls read like Go's table.

;; stop i: position and colour, four f64 at 0x100 + 32*i
(func $stop (param $i i32) (param $pos f64) (param $r f64) (param $g f64) (param $b f64)
  (local $p i32)
  (local.set $p (i32.shl (local.get $i) (i32.const 5)))
  (f64.store offset=0x100 (local.get $p) (local.get $pos))
  (f64.store offset=0x108 (local.get $p) (local.get $r))
  (f64.store offset=0x110 (local.get $p) (local.get $g))
  (f64.store offset=0x118 (local.get $p) (local.get $b)))

;; f2b maps [0, 1] to a byte, rounding half up. Inside the range v*255 + 0.5
;; is positive and below 256, so the unsigned truncation is in range.
(func $f2b (param $v f64) (result i32)
  (if (result i32) (f64.le (local.get $v) (f64.const 0))
    (then (i32.const 0))
    (else
      (if (result i32) (f64.ge (local.get $v) (f64.const 1))
        (then (i32.const 255))
        (else (i32.trunc_f64_u (f64.add (f64.mul (local.get $v) (f64.const 255))
                                        (f64.const 0.5))))))))

;; rgb packs three [0, 1] channels as 0xFFBBGGRR: canvas.FromFloat
(func $rgb (param $r f64) (param $g f64) (param $b f64) (result i32)
  (i32.or
    (i32.or (i32.const 0xFF000000)
            (i32.shl (call $f2b (local.get $b)) (i32.const 16)))
    (i32.or (i32.shl (call $f2b (local.get $g)) (i32.const 8))
            (call $f2b (local.get $r)))))

;; build_palette: palette.New over the n stops at 0x100, into 256 u32 at $dst
(func $build_palette (param $dst i32) (param $n i32)
  (local $i i32) (local $t f64) (local $k i32)
  (local $a i32) (local $b i32) (local $u f64)
  (loop $each
    (local.set $t (f64.div (f64.convert_i32_s (local.get $i)) (f64.const 255)))
    ;; find the segment containing t; the default is first stop to last
    (local.set $a (i32.const 0x100))
    (local.set $b (i32.add (i32.const 0x100)
                           (i32.shl (i32.sub (local.get $n) (i32.const 1)) (i32.const 5))))
    (local.set $k (i32.const 0x100))
    (block $found
      (loop $seek
        (br_if $found (i32.ge_u (local.get $k) (local.get $b)))
        (if (i32.and (f64.ge (local.get $t) (f64.load (local.get $k)))
                     (f64.le (local.get $t) (f64.load offset=32 (local.get $k))))
          (then
            (local.set $a (local.get $k))
            (local.set $b (i32.add (local.get $k) (i32.const 32)))
            (br $found)))
        (local.set $k (i32.add (local.get $k) (i32.const 32)))
        (br $seek)))
    ;; u: where t sits in the segment, clamped, then smoothstepped
    (local.set $u (f64.const 0))
    (if (f64.gt (f64.load (local.get $b)) (f64.load (local.get $a)))
      (then (local.set $u (f64.div (f64.sub (local.get $t) (f64.load (local.get $a)))
                                   (f64.sub (f64.load (local.get $b)) (f64.load (local.get $a)))))))
    (local.set $u (f64.min (f64.max (local.get $u) (f64.const 0)) (f64.const 1)))
    (local.set $u (f64.mul (f64.mul (local.get $u) (local.get $u))
                           (f64.sub (f64.const 3) (f64.mul (f64.const 2) (local.get $u)))))
    ;; each channel is a.c + (b.c - a.c)*u, at byte offsets 8, 16, 24 of a stop
    (i32.store (i32.add (local.get $dst) (i32.shl (local.get $i) (i32.const 2)))
      (call $rgb
        (f64.add (f64.load offset=8 (local.get $a))
                 (f64.mul (f64.sub (f64.load offset=8 (local.get $b))
                                   (f64.load offset=8 (local.get $a))) (local.get $u)))
        (f64.add (f64.load offset=16 (local.get $a))
                 (f64.mul (f64.sub (f64.load offset=16 (local.get $b))
                                   (f64.load offset=16 (local.get $a))) (local.get $u)))
        (f64.add (f64.load offset=24 (local.get $a))
                 (f64.mul (f64.sub (f64.load offset=24 (local.get $b))
                                   (f64.load offset=24 (local.get $a))) (local.get $u)))))
    (local.set $i (i32.add (local.get $i) (i32.const 1)))
    (br_if $each (i32.lt_u (local.get $i) (i32.const 256)))))

(func $build_palettes
  ;; SUNSET: deep violet to hot orange to cream
  (call $stop (i32.const 0) (f64.const 0.00) (f64.const 0.02) (f64.const 0.00) (f64.const 0.06))
  (call $stop (i32.const 1) (f64.const 0.18) (f64.const 0.25) (f64.const 0.02) (f64.const 0.38))
  (call $stop (i32.const 2) (f64.const 0.38) (f64.const 0.72) (f64.const 0.05) (f64.const 0.45))
  (call $stop (i32.const 3) (f64.const 0.56) (f64.const 0.98) (f64.const 0.25) (f64.const 0.22))
  (call $stop (i32.const 4) (f64.const 0.74) (f64.const 1.00) (f64.const 0.62) (f64.const 0.15))
  (call $stop (i32.const 5) (f64.const 0.88) (f64.const 1.00) (f64.const 0.93) (f64.const 0.55))
  (call $stop (i32.const 6) (f64.const 1.00) (f64.const 1.00) (f64.const 1.00) (f64.const 0.96))
  (call $build_palette (i32.const 0x13000) (i32.const 7))
  ;; ICE: the cold counterpart, for the tunnel and the mandelbrot
  (call $stop (i32.const 0) (f64.const 0.00) (f64.const 0.00) (f64.const 0.00) (f64.const 0.03))
  (call $stop (i32.const 1) (f64.const 0.25) (f64.const 0.00) (f64.const 0.10) (f64.const 0.30))
  (call $stop (i32.const 2) (f64.const 0.50) (f64.const 0.00) (f64.const 0.55) (f64.const 0.85))
  (call $stop (i32.const 3) (f64.const 0.72) (f64.const 0.35) (f64.const 0.90) (f64.const 1.00))
  (call $stop (i32.const 4) (f64.const 0.90) (f64.const 0.80) (f64.const 1.00) (f64.const 1.00))
  (call $stop (i32.const 5) (f64.const 1.00) (f64.const 1.00) (f64.const 1.00) (f64.const 1.00))
  (call $build_palette (i32.const 0x13400) (i32.const 6))
  ;; EMBER: the fire ramp
  (call $stop (i32.const 0) (f64.const 0.00) (f64.const 0.00) (f64.const 0.00) (f64.const 0.00))
  (call $stop (i32.const 1) (f64.const 0.20) (f64.const 0.25) (f64.const 0.00) (f64.const 0.00))
  (call $stop (i32.const 2) (f64.const 0.45) (f64.const 0.80) (f64.const 0.10) (f64.const 0.00))
  (call $stop (i32.const 3) (f64.const 0.68) (f64.const 1.00) (f64.const 0.45) (f64.const 0.00))
  (call $stop (i32.const 4) (f64.const 0.85) (f64.const 1.00) (f64.const 0.80) (f64.const 0.15))
  (call $stop (i32.const 5) (f64.const 1.00) (f64.const 1.00) (f64.const 1.00) (f64.const 0.85))
  (call $build_palette (i32.const 0x13800) (i32.const 6)))
