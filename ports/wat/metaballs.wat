;; METABALLS: six radial fields summed, the iso-contour shaded
;;
;; Each pixel evaluates sum(r^2 / d^2): one division per ball, no square
;; root. The per-ball constants of a frame sit at 0x800, 16 bytes a ball:
;;   +0 offset x = (ball x - 0.5) * aspect   +4 offset y = ball y - 0.5
;;   +8 r^2
;; Go recomputes the two offsets for every pixel; they are the same f32
;; values either way, so computing them once changes no pixel.

(func $metaballs_render (param $t f32)
  (local $i i32) (local $fi f32) (local $a f32) (local $bx f32) (local $by f32)
  (local $rad f32) (local $asp f32)
  (local $x i32) (local $y i32) (local $px i32) (local $ball i32)
  (local $fx f32) (local $fy f32) (local $dx f32) (local $dy f32)
  (local $field f32) (local $idx i32)
  (local.set $asp (f32.div (f32.convert_i32_s (global.get $W)) (f32.convert_i32_s (global.get $H))))
  ;; Prepare: each ball orbits on its own ellipse and breathes
  (loop $balls
    (local.set $fi (f32.convert_i32_s (local.get $i)))
    (local.set $a (f32.add (f32.mul (local.get $t)
                                    (f32.add (f32.const 0.35) (f32.mul (local.get $fi) (f32.const 0.07))))
                           (f32.mul (local.get $fi) (f32.const 2.1))))
    ;; x = 0.5 + 0.20*cos(a) * (1 + 0.3*sin(t*0.5 + fi))
    (local.set $bx
      (f32.add (f32.const 0.5)
        (f32.mul (f32.mul (f32.const 0.20) (call $cos (local.get $a)))
                 (f32.add (f32.const 1)
                          (f32.mul (f32.const 0.3)
                                   (call $sin (f32.add (f32.mul (local.get $t) (f32.const 0.5))
                                                       (local.get $fi))))))))
    ;; y = 0.5 + 0.20*sin(a*1.3 + fi) * (1 + 0.3*cos(t*0.4 + fi*2))
    (local.set $by
      (f32.add (f32.const 0.5)
        (f32.mul (f32.mul (f32.const 0.20)
                          (call $sin (f32.add (f32.mul (local.get $a) (f32.const 1.3)) (local.get $fi))))
                 (f32.add (f32.const 1)
                          (f32.mul (f32.const 0.3)
                                   (call $cos (f32.add (f32.mul (local.get $t) (f32.const 0.4))
                                                       (f32.mul (local.get $fi) (f32.const 2)))))))))
    (local.set $rad
      (f32.add (f32.const 0.105)
               (f32.mul (f32.const 0.025)
                        (call $sin (f32.add (f32.mul (local.get $t) (f32.const 1.1))
                                            (f32.mul (local.get $fi) (f32.const 1.7)))))))
    (local.set $ball (i32.shl (local.get $i) (i32.const 4)))
    (f32.store offset=0x800 (local.get $ball)
               (f32.mul (f32.sub (local.get $bx) (f32.const 0.5)) (local.get $asp)))
    (f32.store offset=0x804 (local.get $ball) (f32.sub (local.get $by) (f32.const 0.5)))
    (f32.store offset=0x808 (local.get $ball) (f32.mul (local.get $rad) (local.get $rad)))
    (local.set $i (i32.add (local.get $i) (i32.const 1)))
    (br_if $balls (i32.lt_u (local.get $i) (i32.const 6))))

  (local.set $px (i32.const 0x120000))
  ;; @excerpt METABALLS
  (loop $rows
    (local.set $fy (f32.sub (f32.div (f32.convert_i32_s (local.get $y))
                                     (f32.convert_i32_s (global.get $H)))
                            (f32.const 0.5)))
    (local.set $x (i32.const 0))
    (loop $cols
      ;; x scaled by the aspect ratio, so a circle in field space is round
      (local.set $fx (f32.mul (f32.sub (f32.div (f32.convert_i32_s (local.get $x))
                                                (f32.convert_i32_s (global.get $W)))
                                       (f32.const 0.5))
                              (local.get $asp)))
      (local.set $field (f32.const 0))
      (local.set $ball (i32.const 0))
      (loop $sum
        (local.set $dx (f32.sub (local.get $fx) (f32.load offset=0x800 (local.get $ball))))
        (local.set $dy (f32.sub (local.get $fy) (f32.load offset=0x804 (local.get $ball))))
        ;; field += r^2 / (dx*dx + dy*dy + 1e-5)
        (local.set $field
          (f32.add (local.get $field)
                   (f32.div (f32.load offset=0x808 (local.get $ball))
                            (f32.add (f32.add (f32.mul (local.get $dx) (local.get $dx))
                                              (f32.mul (local.get $dy) (local.get $dy)))
                                     (f32.const 1e-5)))))
        (local.set $ball (i32.add (local.get $ball) (i32.const 16)))
        (br_if $sum (i32.lt_u (local.get $ball) (i32.const 96))))
      ;; field/(1.6 + field) squeezes 0..inf into 0..1 without a log
      (local.set $idx (i32.trunc_f32_s
                        (f32.mul (f32.div (local.get $field) (f32.add (f32.const 1.6) (local.get $field)))
                                 (f32.const 255))))
      (local.set $idx (select (i32.const 255) (local.get $idx)
                              (i32.gt_s (local.get $idx) (i32.const 255))))
      ;; the rim: where the balls meet, the iso-surface flares white
      (if (i32.and (f32.gt (local.get $field) (f32.const 1.0))
                   (f32.lt (local.get $field) (f32.const 1.09)))
        (then (local.set $idx (i32.const 255))))
      (i32.store (local.get $px)
                 (i32.load offset=0x13000 (i32.shl (local.get $idx) (i32.const 2))))  ;; SUNSET
      (local.set $px (i32.add (local.get $px) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H))))
  ;; @end
  )
