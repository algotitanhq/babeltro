;; STARFIELD: warp-speed stars, projected in perspective, drawn as streaks
;;
;; SCRATCH holds the backdrop (w*h u32, built once per start), then 1600
;; stars of 16 bytes (x, y, z f32), then 1600 projected streaks of 20 bytes
;; (x0, y0, x1, y1 i32 and the colour).

(global $sf_stars (mut i32) (i32.const 0))
(global $sf_proj  (mut i32) (i32.const 0))

;; fmath.Rng: xorshift32, shared by the starfield and the finale (only one
;; runs at a time, and each seeds it at start)
(global $rng (mut i32) (i32.const 0))

(func $rng_next (result i32)
  (local $x i32)
  (local.set $x (global.get $rng))
  (local.set $x (i32.xor (local.get $x) (i32.shl   (local.get $x) (i32.const 13))))
  (local.set $x (i32.xor (local.get $x) (i32.shr_u (local.get $x) (i32.const 17))))
  (local.set $x (i32.xor (local.get $x) (i32.shl   (local.get $x) (i32.const 5))))
  (global.set $rng (local.get $x))
  (local.get $x))

;; a float in [0, 1) from the top 24 bits: exact in f32, so the same in
;; every language. convert_i32_u, since the bits are unsigned.
(func $rng_float32 (result f32)
  (f32.mul (f32.convert_i32_u (i32.shr_u (call $rng_next) (i32.const 8)))
           (f32.const 5.9604644775390625e-8)))                  ;; 1/16777216

;; (f*2 - 1) * k, the starfield's spread
(func $rng_spread (param $k f32) (result f32)
  (f32.mul (f32.sub (f32.mul (call $rng_float32) (f32.const 2)) (f32.const 1)) (local.get $k)))

(func $starfield_start
  (local $p i32) (local $end i32) (local $x i32) (local $y i32)
  (local $dx f64) (local $dy f64) (local $v f64)
  (global.set $sf_stars (i32.add (global.get $SCRATCH)
                                 (i32.shl (i32.mul (global.get $W) (global.get $H)) (i32.const 2))))
  (global.set $sf_proj (i32.add (global.get $sf_stars) (i32.const 25600)))
  (global.set $rng (i32.const 0x6005E))
  ;; three draws per star, in order: x, then y, then z
  (local.set $p (global.get $sf_stars))
  (local.set $end (global.get $sf_proj))
  (loop $seed
    (f32.store (local.get $p) (call $rng_spread (f32.const 1.6)))
    (f32.store offset=4 (local.get $p) (call $rng_spread (f32.const 1.6)))
    (f32.store offset=8 (local.get $p)
               (f32.add (f32.mul (call $rng_float32) (f32.const 40)) (f32.const 0.2)))
    (local.set $p (i32.add (local.get $p) (i32.const 16)))
    (br_if $seed (i32.lt_u (local.get $p) (local.get $end))))
  ;; the deep-navy vignette, once: copying a ready image beats recomputing it
  (local.set $p (global.get $SCRATCH))
  (loop $rows
    (local.set $dy (f64.sub (f64.div (f64.convert_i32_s (local.get $y)) (f64.convert_i32_s (global.get $H)))
                            (f64.const 0.5)))
    (local.set $x (i32.const 0))
    (loop $cols
      (local.set $dx (f64.sub (f64.div (f64.convert_i32_s (local.get $x)) (f64.convert_i32_s (global.get $W)))
                              (f64.const 0.5)))
      (local.set $v (f64.add (f64.mul (local.get $dx) (local.get $dx)) (f64.mul (local.get $dy) (local.get $dy))))
      ;; Go clamps each channel at 0 first; $f2b maps anything <= 0 to 0 anyway
      (i32.store (local.get $p)
        (call $rgb (f64.sub (f64.const 0.02) (f64.mul (local.get $v) (f64.const 0.03)))
                   (f64.sub (f64.const 0.02) (f64.mul (local.get $v) (f64.const 0.025)))
                   (f64.sub (f64.const 0.05) (f64.mul (local.get $v) (f64.const 0.03)))))
      (local.set $p (i32.add (local.get $p) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H)))))

;; line_add: Bresenham from (x0, y0) to (x1, y1), adding c with saturation,
;; so crossing stars brighten instead of hiding each other
(func $line_add (param $x0 i32) (param $y0 i32) (param $x1 i32) (param $y1 i32) (param $c i32)
  (local $dx i32) (local $dy i32) (local $sx i32) (local $sy i32) (local $err i32) (local $e2 i32)
  (local $a i32) (local $p i32)
  (local.set $dx (i32.sub (local.get $x1) (local.get $x0)))
  (local.set $dx (select (i32.sub (i32.const 0) (local.get $dx)) (local.get $dx)
                         (i32.lt_s (local.get $dx) (i32.const 0))))
  (local.set $dy (i32.sub (local.get $y1) (local.get $y0)))
  (local.set $dy (select (local.get $dy) (i32.sub (i32.const 0) (local.get $dy))   ;; -|dy|
                         (i32.lt_s (local.get $dy) (i32.const 0))))
  (local.set $sx (select (i32.const 1) (i32.const -1) (i32.lt_s (local.get $x0) (local.get $x1))))
  (local.set $sy (select (i32.const 1) (i32.const -1) (i32.lt_s (local.get $y0) (local.get $y1))))
  (local.set $err (i32.add (local.get $dx) (local.get $dy)))
  (loop $step
    (if (i32.and (i32.lt_u (local.get $x0) (global.get $W)) (i32.lt_u (local.get $y0) (global.get $H)))
      (then
        (local.set $a (i32.add (i32.const 0x120000)
                               (i32.shl (i32.add (i32.mul (local.get $y0) (global.get $W)) (local.get $x0))
                                        (i32.const 2))))
        (local.set $p (i32.load (local.get $a)))
        (i32.store (local.get $a)
          (call $pack_sat
            (i32.add (i32.and (local.get $p) (i32.const 0xFF)) (i32.and (local.get $c) (i32.const 0xFF)))
            (i32.add (call $ch (local.get $p) (i32.const 1)) (call $ch (local.get $c) (i32.const 1)))
            (i32.add (call $ch (local.get $p) (i32.const 2)) (call $ch (local.get $c) (i32.const 2)))))))
    (if (i32.and (i32.eq (local.get $x0) (local.get $x1)) (i32.eq (local.get $y0) (local.get $y1)))
      (then (return)))
    (local.set $e2 (i32.shl (local.get $err) (i32.const 1)))
    (if (i32.ge_s (local.get $e2) (local.get $dy))
      (then (local.set $err (i32.add (local.get $err) (local.get $dy)))
            (local.set $x0 (i32.add (local.get $x0) (local.get $sx)))))
    (if (i32.le_s (local.get $e2) (local.get $dx))
      (then (local.set $err (i32.add (local.get $err) (local.get $dx)))
            (local.set $y0 (i32.add (local.get $y0) (local.get $sy)))))
    (br $step)))

(func $starfield_render (param $t f64)
  (local $p i32) (local $q i32) (local $end i32)
  (local $cx f32) (local $cy f32) (local $dz f32) (local $zoom f32)
  (local $x f32) (local $y f32) (local $z f32) (local $f f32) (local $f2 f32)
  (local $near f32) (local $b f32) (local $x1 i32) (local $y1 i32)
  (local.set $cx (f32.mul (f32.convert_i32_s (global.get $W)) (f32.const 0.5)))
  (local.set $cy (f32.mul (f32.convert_i32_s (global.get $H)) (f32.const 0.5)))
  ;; speed = float32(2.5 + min(t, 3)*4), in f64 then rounded; dt is
  ;; float32(1/60) (under Go's 0.1 cap)
  (local.set $dz (f32.mul (f32.demote_f64 (f64.add (f64.const 2.5)
                                                   (f64.mul (f64.min (local.get $t) (f64.const 3)) (f64.const 4))))
                          (f32.demote_f64 (f64.div (f64.const 1) (f64.const 60)))))
  (local.set $zoom (f32.mul (f32.convert_i32_s (global.get $W)) (f32.const 0.78)))
  (local.set $p (global.get $sf_stars))
  (local.set $q (global.get $sf_proj))
  (local.set $end (global.get $sf_proj))
  ;; @excerpt STARFIELD
  (loop $stars
    (local.set $z (f32.sub (f32.load offset=8 (local.get $p)) (local.get $dz)))
    (if (f32.lt (local.get $z) (f32.const 0.8))
      (then                                    ;; past the camera: respawn far away
        (local.set $z (f32.add (local.get $z) (f32.const 40)))
        (f32.store (local.get $p) (call $rng_spread (f32.const 1.1)))
        (f32.store offset=4 (local.get $p) (call $rng_spread (f32.const 1.1)))))
    (f32.store offset=8 (local.get $p) (local.get $z))
    (local.set $x (f32.load (local.get $p)))
    (local.set $y (f32.load offset=4 (local.get $p)))
    ;; the head at depth z, the tail where the star was 2.4 frames ago
    (local.set $f (f32.div (f32.const 1) (local.get $z)))
    (local.set $f2 (f32.div (f32.const 1) (f32.add (local.get $z) (f32.mul (local.get $dz) (f32.const 2.4)))))
    (i32.store (local.get $q)
      (i32.trunc_f32_s (f32.add (local.get $cx) (f32.mul (f32.mul (local.get $x) (local.get $f)) (local.get $zoom)))))
    (i32.store offset=4 (local.get $q)
      (i32.trunc_f32_s (f32.add (local.get $cy) (f32.mul (f32.mul (local.get $y) (local.get $f)) (local.get $zoom)))))
    (i32.store offset=8 (local.get $q)
      (i32.trunc_f32_s (f32.add (local.get $cx) (f32.mul (f32.mul (local.get $x) (local.get $f2)) (local.get $zoom)))))
    (i32.store offset=12 (local.get $q)
      (i32.trunc_f32_s (f32.add (local.get $cy) (f32.mul (f32.mul (local.get $y) (local.get $f2)) (local.get $zoom)))))
    ;; brighter and bluer as the star gets close
    (local.set $near (f32.sub (f32.const 1) (f32.div (local.get $z) (f32.const 40))))
    (local.set $b (f32.mul (local.get $near) (local.get $near)))
    (i32.store offset=16 (local.get $q)
      (i32.or
        (i32.or (i32.const 0xFF000000)
                (i32.shl (i32.trunc_f32_u (f32.mul (f32.const 255)
                                                   (f32.add (f32.const 0.25) (f32.mul (f32.const 0.75) (local.get $b)))))
                         (i32.const 16)))
        (i32.or (i32.shl (i32.trunc_f32_u (f32.add (f32.mul (f32.const 190) (local.get $b)) (f32.const 40)))
                         (i32.const 8))
                (i32.trunc_f32_u (f32.add (f32.mul (f32.const 120) (local.get $b)) (f32.const 40))))))
    (local.set $p (i32.add (local.get $p) (i32.const 16)))
    (local.set $q (i32.add (local.get $q) (i32.const 20)))
    (br_if $stars (i32.lt_u (local.get $p) (local.get $end))))
  ;; @end

  ;; Draw: the backdrop in one memory.copy, then every streak and its head
  (memory.copy (i32.const 0x120000) (global.get $SCRATCH)
               (i32.shl (i32.mul (global.get $W) (global.get $H)) (i32.const 2)))
  (local.set $q (global.get $sf_proj))
  (local.set $end (i32.add (local.get $q) (i32.const 32000)))
  (loop $draw
    (local.set $x1 (i32.load offset=8 (local.get $q)))
    (local.set $y1 (i32.load offset=12 (local.get $q)))
    (call $line_add (i32.load (local.get $q)) (i32.load offset=4 (local.get $q))
                    (local.get $x1) (local.get $y1) (i32.load offset=16 (local.get $q)))
    (if (i32.and (i32.lt_u (local.get $x1) (global.get $W)) (i32.lt_u (local.get $y1) (global.get $H)))
      (then (i32.store offset=0x120000
              (i32.shl (i32.add (i32.mul (local.get $y1) (global.get $W)) (local.get $x1)) (i32.const 2))
              (i32.const 0xFFCCEEFF))))
    (local.set $q (i32.add (local.get $q) (i32.const 20)))
    (br_if $draw (i32.lt_u (local.get $q) (local.get $end)))))
