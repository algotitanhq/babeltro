;; ROTOZOOM: build a texture once, then rotate and zoom the sampling grid
;;
;; The texture is 512x512 u32 at 0x20000, built the first time the scene
;; starts and kept for the life of the module (it never depends on the
;; screen size). Building it takes about a million calls to $sin64: this is
;; where a sine written from scratch has to be good in f64, not just in f32.

(global $tex_ready (mut i32) (i32.const 0))

;; hue2rgb and hsl2rgb are palette.HSL2RGB. hsl2rgb returns three values:
;; with multi-value a function's result is any sequence of types, left on
;; the stack in order, so r g b come back without a struct or a pointer.
(func $hue2rgb (param $p f64) (param $q f64) (param $t f64) (result f64)
  (if (f64.lt (local.get $t) (f64.const 0))
    (then (local.set $t (f64.add (local.get $t) (f64.const 1)))))
  (if (f64.gt (local.get $t) (f64.const 1))
    (then (local.set $t (f64.sub (local.get $t) (f64.const 1)))))
  (if (f64.lt (local.get $t) (f64.const 0.16666666666666666))      ;; 1/6
    (then (return (f64.add (local.get $p)
                           (f64.mul (f64.mul (f64.sub (local.get $q) (local.get $p)) (f64.const 6))
                                    (local.get $t))))))
  (if (f64.lt (local.get $t) (f64.const 0.5))
    (then (return (local.get $q))))
  (if (f64.lt (local.get $t) (f64.const 0.6666666666666666))       ;; 2/3
    (then (return (f64.add (local.get $p)
                           (f64.mul (f64.mul (f64.sub (local.get $q) (local.get $p))
                                             (f64.sub (f64.const 0.6666666666666666) (local.get $t)))
                                    (f64.const 6))))))
  (local.get $p))

(func $hsl2rgb (param $h f64) (param $s f64) (param $l f64) (result f64 f64 f64)
  (local $q f64) (local $p f64)
  (local.set $q
    (if (result f64) (f64.lt (local.get $l) (f64.const 0.5))
      (then (f64.mul (local.get $l) (f64.add (f64.const 1) (local.get $s))))
      (else (f64.sub (f64.add (local.get $l) (local.get $s))
                     (f64.mul (local.get $l) (local.get $s))))))
  (local.set $p (f64.sub (f64.mul (f64.const 2) (local.get $l)) (local.get $q)))
  (call $hue2rgb (local.get $p) (local.get $q)
                 (f64.add (local.get $h) (f64.const 0.3333333333333333)))   ;; 1/3
  (call $hue2rgb (local.get $p) (local.get $q) (local.get $h))
  (call $hue2rgb (local.get $p) (local.get $q)
                 (f64.sub (local.get $h) (f64.const 0.3333333333333333))))

;; build_texture: a tileable rainbow plasma with a dark grid over it. Every
;; frequency is a whole number of cycles per tile, so it wraps every 512
;; pixels. All f64, with fx and fy first rounded to f32 as Go's are.
(func $build_texture
  (local $x i32) (local $y i32) (local $fx f64) (local $fy f64)
  (local $v f64) (local $dx f64) (local $dy f64) (local $rr f64) (local $hue f64)
  (local $r f64) (local $g f64) (local $b f64)
  (loop $rows
    (local.set $fy (f64.promote_f32 (f32.div (f32.convert_i32_s (local.get $y)) (f32.const 512))))
    (local.set $x (i32.const 0))
    (loop $cols
      (local.set $fx (f64.promote_f32 (f32.div (f32.convert_i32_s (local.get $x)) (f32.const 512))))
      ;; v = sin(fx*2pi*3 + fy*2pi*2)*0.5 + sin(fy*2pi*5 - fx*2pi*4)*0.3
      ;;   + sin((fx + fy)*2pi*7)*0.2
      (local.set $v
        (f64.add
          (f64.add
            (f64.mul (call $sin64
                       (f64.add (f64.mul (f64.mul (local.get $fx) (f64.const 6.283185307179586)) (f64.const 3))
                                (f64.mul (f64.mul (local.get $fy) (f64.const 6.283185307179586)) (f64.const 2))))
                     (f64.const 0.5))
            (f64.mul (call $sin64
                       (f64.sub (f64.mul (f64.mul (local.get $fy) (f64.const 6.283185307179586)) (f64.const 5))
                                (f64.mul (f64.mul (local.get $fx) (f64.const 6.283185307179586)) (f64.const 4))))
                     (f64.const 0.3)))
          (f64.mul (call $sin64
                     (f64.mul (f64.mul (f64.add (local.get $fx) (local.get $fy)) (f64.const 6.283185307179586))
                              (f64.const 7)))
                   (f64.const 0.2))))
      ;; concentric rings, also periodic in the tile
      (local.set $dx (f64.sub (f64.convert_i32_s (local.get $x)) (f64.const 256)))
      (local.set $dy (f64.sub (f64.convert_i32_s (local.get $y)) (f64.const 256)))
      (local.set $rr (f64.mul (f64.div (f64.sqrt (f64.add (f64.mul (local.get $dx) (local.get $dx))
                                                          (f64.mul (local.get $dy) (local.get $dy))))
                                       (f64.const 512))
                              (f64.const 12)))
      (local.set $v (f64.add (local.get $v)
                             (f64.mul (call $sin64 (f64.mul (local.get $rr) (f64.const 6.283185307179586)))
                                      (f64.const 0.35))))
      ;; hue = math.Mod(v*0.55 + 0.5, 1): for a value this small, x - trunc(x)
      ;; is exact, and keeps the sign of x as Mod does
      (local.set $hue (f64.add (f64.mul (local.get $v) (f64.const 0.55)) (f64.const 0.5)))
      (local.set $hue (f64.sub (local.get $hue) (f64.trunc (local.get $hue))))
      (if (f64.lt (local.get $hue) (f64.const 0))
        (then (local.set $hue (f64.add (local.get $hue) (f64.const 1)))))
      (call $hsl2rgb (local.get $hue) (f64.const 0.70)
                     (f64.add (f64.const 0.48) (f64.mul (f64.const 0.14) (local.get $v))))
      (local.set $b) (local.set $g) (local.set $r)        ;; popped in reverse
      ;; the dark grid: without a straight edge, rotation reads as shimmer
      (if (i32.or (i32.lt_u (i32.and (local.get $x) (i32.const 63)) (i32.const 3))
                  (i32.lt_u (i32.and (local.get $y) (i32.const 63)) (i32.const 3)))
        (then
          (local.set $r (f64.mul (local.get $r) (f64.const 0.28)))
          (local.set $g (f64.mul (local.get $g) (f64.const 0.28)))
          (local.set $b (f64.mul (local.get $b) (f64.const 0.28)))))
      (i32.store offset=0x20000                          ;; TEXTURE
        (i32.shl (i32.add (i32.shl (local.get $y) (i32.const 9)) (local.get $x)) (i32.const 2))
        (call $rgb (local.get $r) (local.get $g) (local.get $b)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_u (local.get $x) (i32.const 512))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_u (local.get $y) (i32.const 512)))))

(func $rotozoom_start
  (if (i32.eqz (global.get $tex_ready))
    (then (call $build_texture) (global.set $tex_ready (i32.const 1)))))

(func $rotozoom_render (param $t f32)
  (local $x i32) (local $y i32) (local $px i32)
  (local $cx f32) (local $cy f32) (local $dx f32) (local $dy f32)
  (local $cosA f32) (local $sinA f32) (local $zoom f32) (local $offx f32) (local $offy f32)
  (local $tx f32) (local $ty f32)
  ;; Prepare: angle, breathing zoom (0.7 .. 1.6) and drift, from the table
  (local.set $cosA (call $cos (f32.mul (local.get $t) (f32.const 0.45))))
  (local.set $sinA (call $sin (f32.mul (local.get $t) (f32.const 0.45))))
  (local.set $zoom (f32.add (f32.add (f32.const 0.55)
                                     (f32.mul (f32.const 0.45)
                                              (call $sin (f32.mul (local.get $t) (f32.const 0.7)))))
                            (f32.const 0.35)))
  (local.set $offx (f32.add (f32.mul (call $sin (f32.mul (local.get $t) (f32.const 0.31))) (f32.const 180))
                            (f32.mul (local.get $t) (f32.const 26))))
  (local.set $offy (f32.add (f32.mul (call $cos (f32.mul (local.get $t) (f32.const 0.27))) (f32.const 180))
                            (f32.mul (local.get $t) (f32.const 19))))
  ;; Draw
  (local.set $cx (f32.mul (f32.convert_i32_s (global.get $W)) (f32.const 0.5)))
  (local.set $cy (f32.mul (f32.convert_i32_s (global.get $H)) (f32.const 0.5)))
  (local.set $zoom (f32.mul (f32.div (local.get $zoom) (f32.convert_i32_s (global.get $W)))
                            (f32.const 6.5)))
  (local.set $px (i32.const 0x120000))
  ;; @excerpt ROTOZOOM
  (loop $rows
    (local.set $dy (f32.sub (f32.convert_i32_s (local.get $y)) (local.get $cy)))
    (local.set $x (i32.const 0))
    (loop $cols
      (local.set $dx (f32.sub (f32.convert_i32_s (local.get $x)) (local.get $cx)))
      ;; rotate, then zoom: two separate multiplies, as Go writes them,
      ;; because (zoom*34) folded into one constant would round differently
      (local.set $tx (f32.mul (f32.mul (f32.sub (f32.mul (local.get $dx) (local.get $cosA))
                                                (f32.mul (local.get $dy) (local.get $sinA)))
                                       (local.get $zoom))
                              (f32.const 34)))
      (local.set $ty (f32.mul (f32.mul (f32.add (f32.mul (local.get $dx) (local.get $sinA))
                                                (f32.mul (local.get $dy) (local.get $cosA)))
                                       (local.get $zoom))
                              (f32.const 34)))
      ;; wrap into the 512x512 tile with & 511: a negative coordinate wraps
      ;; too, since truncation toward zero then two's complement does it
      (i32.store (local.get $px)
        (i32.load offset=0x20000                         ;; TEXTURE[iy*512 + ix]
          (i32.shl
            (i32.or
              (i32.shl (i32.and (i32.trunc_f32_s (f32.add (local.get $ty) (local.get $offy)))
                                (i32.const 511))
                       (i32.const 9))
              (i32.and (i32.trunc_f32_s (f32.add (local.get $tx) (local.get $offx)))
                       (i32.const 511)))
            (i32.const 2))))
      (local.set $px (i32.add (local.get $px) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H))))
  ;; @end
  )
