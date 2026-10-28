;; FIRE: the Doom fire, one byte of heat per pixel, diffused upward
;;
;; Integer work only, and the one scene whose state outlives a frame: the
;; heat buffer (w*h bytes at SCRATCH) and the generator's state.

(global $fire_rng (mut i32) (i32.const 0))

;; fire_start: a cold buffer and the seed, as Go's NewFire. memory.fill is the
;; bulk-memory feature: one instruction, the engine's own memset.
(func $fire_start
  (memory.fill (global.get $SCRATCH) (i32.const 0)
               (i32.mul (global.get $W) (global.get $H)))
  (global.set $fire_rng (i32.const 0x9E3779B9)))

;; xorshift32: three shifts, three xors, the same sequence in every
;; language. shr_u, because the state is unsigned: Go's >> on a uint32
;; shifts zeros in, where shr_s would copy the sign bit.
(func $fire_rand (result i32)
  (local $x i32)
  (local.set $x (global.get $fire_rng))
  (local.set $x (i32.xor (local.get $x) (i32.shl   (local.get $x) (i32.const 13))))
  (local.set $x (i32.xor (local.get $x) (i32.shr_u (local.get $x) (i32.const 17))))
  (local.set $x (i32.xor (local.get $x) (i32.shl   (local.get $x) (i32.const 5))))
  (global.set $fire_rng (local.get $x))
  (local.get $x))

;; fire_palette_row: pixels [px, px + 4w) from heat bytes [b, b + w)
(func $fire_palette_row (param $b i32) (param $px i32)
  (local $end i32)
  (local.set $end (i32.add (local.get $b) (global.get $W)))
  (loop $each
    (i32.store (local.get $px)
      (i32.load offset=0x13800 (i32.shl (i32.load8_u (local.get $b)) (i32.const 2))))  ;; EMBER
    (local.set $px (i32.add (local.get $px) (i32.const 4)))
    (local.set $b (i32.add (local.get $b) (i32.const 1)))
    (br_if $each (i32.lt_u (local.get $b) (local.get $end)))))

(func $fire_render (param $frame i32)
  (local $w i32) (local $x i32) (local $y i32) (local $r i32) (local $sx i32)
  (local $v i32) (local $decay i32)
  (local $src i32) (local $dst i32)
  (local $t f32) (local $fx f32) (local $wv f32) (local $hot f32)
  (local.set $w (global.get $W))

  ;; seed the hottest row: a slow horizontal wave for an uneven base, a
  ;; random term so the tongues never look periodic
  (local.set $dst (i32.add (global.get $SCRATCH)
                           (i32.mul (i32.sub (global.get $H) (i32.const 1)) (local.get $w))))
  (local.set $t (f32.mul (f32.convert_i32_u (local.get $frame)) (f32.const 0.05)))
  (loop $seed
    (local.set $fx (f32.div (f32.convert_i32_s (local.get $x)) (f32.convert_i32_s (local.get $w))))
    ;; wv = 0.5 + 0.5*sin(fx*11 + t)*0.6 + 0.5*sin(fx*23 - t*1.7)*0.4
    (local.set $wv
      (f32.add
        (f32.add (f32.const 0.5)
                 (f32.mul (f32.mul (f32.const 0.5)
                                   (call $sin (f32.add (f32.mul (local.get $fx) (f32.const 11))
                                                       (local.get $t))))
                          (f32.const 0.6)))
        (f32.mul (f32.mul (f32.const 0.5)
                          (call $sin (f32.sub (f32.mul (local.get $fx) (f32.const 23))
                                              (f32.mul (local.get $t) (f32.const 1.7)))))
                 (f32.const 0.4))))
    ;; hot = 150 + wv*90 + (rand & 31) - 16, clamped to 90..255
    (local.set $hot
      (f32.sub
        (f32.add (f32.add (f32.const 150) (f32.mul (local.get $wv) (f32.const 90)))
                 (f32.convert_i32_u (i32.and (call $fire_rand) (i32.const 31))))
        (f32.const 16)))
    ;; f32.min and f32.max are Go's two comparisons (no NaN can reach them)
    (local.set $hot (f32.max (f32.min (local.get $hot) (f32.const 255)) (f32.const 90)))
    (i32.store8 (i32.add (local.get $dst) (local.get $x)) (i32.trunc_f32_u (local.get $hot)))
    (local.set $x (i32.add (local.get $x) (i32.const 1)))
    (br_if $seed (i32.lt_s (local.get $x) (local.get $w))))
  (call $fire_palette_row (local.get $dst)
        (i32.add (i32.const 0x120000) (i32.shl (i32.sub (local.get $dst) (global.get $SCRATCH))
                                               (i32.const 2))))

  ;; diffuse upward: every pixel of row y-1 takes one value from row y,
  ;; shifted sideways by -1, 0 or +1 and cooled by 0 or 1. Gather, not
  ;; scatter: each byte is written exactly once.
  (local.set $y (i32.sub (global.get $H) (i32.const 1)))
  ;; @excerpt FIRE
  (loop $rows
    (local.set $src (i32.add (global.get $SCRATCH) (i32.mul (local.get $y) (local.get $w))))
    (local.set $dst (i32.sub (local.get $src) (local.get $w)))
    (local.set $x (i32.const 0))
    (loop $cols
      (block $next
        ;; a cold source stays cold, and costs no random number
        (if (i32.eqz (i32.load8_u (i32.add (local.get $src) (local.get $x))))
          (then
            (i32.store8 (i32.add (local.get $dst) (local.get $x)) (i32.const 0))
            (br $next)))
        (local.set $r (call $fire_rand))
        ;; sx = x + r%3 - 1: rem_u, the remainder of an unsigned r
        (local.set $sx (i32.sub (i32.add (local.get $x) (i32.rem_u (local.get $r) (i32.const 3)))
                                (i32.const 1)))
        (local.set $sx (select (i32.const 0) (local.get $sx)
                               (i32.lt_s (local.get $sx) (i32.const 0))))
        (local.set $sx (select (i32.sub (local.get $w) (i32.const 1)) (local.get $sx)
                               (i32.ge_s (local.get $sx) (local.get $w))))
        (local.set $v (i32.load8_u (i32.add (local.get $src) (local.get $sx))))
        (local.set $decay (i32.and (i32.shr_u (local.get $r) (i32.const 16)) (i32.const 1)))
        ;; v - decay, or 0 if that would go below zero
        (i32.store8 (i32.add (local.get $dst) (local.get $x))
          (select (i32.sub (local.get $v) (local.get $decay)) (i32.const 0)
                  (i32.gt_u (local.get $v) (local.get $decay)))))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (local.get $w))))
    ;; the row is final: colour it now, while it is still in the cache
    (call $fire_palette_row (local.get $dst)
          (i32.add (i32.const 0x120000) (i32.shl (i32.sub (local.get $dst) (global.get $SCRATCH))
                                                 (i32.const 2))))
    (local.set $y (i32.sub (local.get $y) (i32.const 1)))
    (br_if $rows (i32.gt_s (local.get $y) (i32.const 0))))
  ;; @end
  )
