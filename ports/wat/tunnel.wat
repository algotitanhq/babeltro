;; TUNNEL: every pixel mapped to polar coordinates once, then only looked up
;;
;; The ladder: rung 1 computes the distance and the angle (a square root, a
;; division and an atan2) for every pixel of every frame; rung 2 (the
;; default) reads them from two tables built by tunnel_start.

(global $tu_depth (mut i32) (i32.const 0))   ;; w*h f32: scale/(r + softness)
(global $tu_angle (mut i32) (i32.const 0))   ;; w*h f32: atan2 as a fraction of a turn

;; angle_turns is Go's fmath.Atan2: float32(math.Atan2(y, x)), our $atan2 in
;; f64, then a turn fraction in [0, 1). 2*pi here is an f32 constant, as Go
;; converts it: the division happens in f32.
(func $angle_turns (param $dy f32) (param $dx f32) (result f32)
  (f32.add
    (f32.div (f32.demote_f64 (call $atan2 (f64.promote_f32 (local.get $dy))
                                          (f64.promote_f32 (local.get $dx))))
             (f32.const 6.2831854820251465))      ;; float32(2*pi)
    (f32.const 0.5)))

(func $tunnel_start
  (local $x i32) (local $y i32) (local $p i32)
  (local $cx f32) (local $cy f32) (local $dx f32) (local $dy f32)
  (local $scale f32) (local $soft f32)
  (global.set $tu_depth (global.get $SCRATCH))
  (global.set $tu_angle (i32.add (global.get $SCRATCH)
                                 (i32.shl (i32.mul (global.get $W) (global.get $H)) (i32.const 2))))
  (local.set $cx (f32.div (f32.convert_i32_s (global.get $W)) (f32.const 2)))
  (local.set $cy (f32.div (f32.convert_i32_s (global.get $H)) (f32.const 2)))
  ;; scale with the diagonal so the rings look the same at any resolution
  (local.set $scale (f32.mul (f32.convert_i32_s (i32.add (global.get $W) (global.get $H)))
                             (f32.const 2.2)))
  (local.set $soft (f32.mul (f32.convert_i32_s (i32.add (global.get $W) (global.get $H)))
                            (f32.const 0.02)))
  (loop $rows
    (local.set $dy (f32.sub (f32.convert_i32_s (local.get $y)) (local.get $cy)))
    (local.set $x (i32.const 0))
    (loop $cols
      (local.set $dx (f32.sub (f32.convert_i32_s (local.get $x)) (local.get $cx)))
      ;; both tables have the framebuffer's layout: one byte offset for all
      (f32.store (i32.add (global.get $tu_depth) (local.get $p))
        (f32.div (local.get $scale)
                 (f32.add (f32.sqrt (f32.add (f32.mul (local.get $dx) (local.get $dx))
                                             (f32.mul (local.get $dy) (local.get $dy))))
                          (local.get $soft))))
      (f32.store (i32.add (global.get $tu_angle) (local.get $p))
        (call $angle_turns (local.get $dy) (local.get $dx)))
      (local.set $p (i32.add (local.get $p) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H)))))

;; @excerpt TUNNEL
;; tunnel_shade is the part both rungs share: depth u and angle v in, one
;; pixel out. Rings along the depth, spokes that twist as they recede, a
;; brick checker, fog.
(func $tunnel_shade (param $u f32) (param $v f32) (param $spin f32) (result i32)
  (local $ring f32) (local $twist f32) (local $val f32) (local $idx i32)
  (local.set $ring (call $sin01 (f32.mul (local.get $u) (f32.const 0.16))))
  (local.set $twist (f32.add (f32.add (f32.mul (local.get $v) (f32.const 12))
                                      (f32.mul (local.get $u) (f32.const 0.09)))
                             (local.get $spin)))
  (local.set $val (f32.add (f32.mul (local.get $ring) (f32.const 0.55))
                           (f32.mul (call $sin01 (local.get $twist)) (f32.const 0.45))))
  ;; the checker: (int(u*0.32) + int(twist)) & 1
  (if (i32.and (i32.add (i32.trunc_f32_s (f32.mul (local.get $u) (f32.const 0.32)))
                        (i32.trunc_f32_s (local.get $twist)))
               (i32.const 1))
    (then (local.set $val (f32.mul (f32.neg (local.get $val)) (f32.const 0.7)))))
  ;; idx = int((val*0.5 + 0.5) * fog * 300), fog = 1/(1 + u*0.02)
  (local.set $idx
    (i32.trunc_f32_s
      (f32.mul
        (f32.mul (f32.add (f32.mul (local.get $val) (f32.const 0.5)) (f32.const 0.5))
                 (f32.div (f32.const 1) (f32.add (f32.const 1)
                                                 (f32.mul (local.get $u) (f32.const 0.02)))))
        (f32.const 300))))
  (local.set $idx (select (i32.const 255) (local.get $idx)
                          (i32.gt_s (local.get $idx) (i32.const 255))))
  (local.set $idx (select (i32.const 0) (local.get $idx)
                          (i32.lt_s (local.get $idx) (i32.const 0))))
  (i32.load offset=0x13400 (i32.shl (local.get $idx) (i32.const 2))))   ;; ICE[idx]

;; the default rung: two loads and the shading per pixel
(func $tunnel_draw (param $tm f32)
  (local $p i32) (local $end i32) (local $adv f32) (local $spin f32)
  (local.set $adv (f32.mul (local.get $tm) (f32.const 3)))
  (local.set $spin (f32.mul (local.get $tm) (f32.const 0.25)))
  (local.set $end (i32.shl (i32.mul (global.get $W) (global.get $H)) (i32.const 2)))
  ;; one loop, no x and no y: $p is the byte offset into the framebuffer
  ;; and into both tables at once
  (loop $each
    (i32.store offset=0x120000 (local.get $p)            ;; FRAMEBUFFER
      (call $tunnel_shade
        (f32.add (f32.load (i32.add (global.get $tu_depth) (local.get $p)))
                 (local.get $adv))                       ;; scroll towards the viewer
        (f32.load (i32.add (global.get $tu_angle) (local.get $p)))
        (local.get $spin)))
    (local.set $p (i32.add (local.get $p) (i32.const 4)))
    (br_if $each (i32.lt_u (local.get $p) (local.get $end))))
  ;; @end
  )

;; rung 1: the tables' formulas, every pixel, every frame
(func $tunnel_draw_direct (param $tm f32)
  (local $x i32) (local $y i32) (local $p i32)
  (local $adv f32) (local $spin f32) (local $cx f32) (local $cy f32)
  (local $scale f32) (local $soft f32) (local $dx f32) (local $dy f32)
  (local.set $adv (f32.mul (local.get $tm) (f32.const 3)))
  (local.set $spin (f32.mul (local.get $tm) (f32.const 0.25)))
  (local.set $cx (f32.div (f32.convert_i32_s (global.get $W)) (f32.const 2)))
  (local.set $cy (f32.div (f32.convert_i32_s (global.get $H)) (f32.const 2)))
  (local.set $scale (f32.mul (f32.convert_i32_s (i32.add (global.get $W) (global.get $H)))
                             (f32.const 2.2)))
  (local.set $soft (f32.mul (f32.convert_i32_s (i32.add (global.get $W) (global.get $H)))
                            (f32.const 0.02)))
  ;; @excerpt TUNNEL/1
  (loop $rows
    (local.set $dy (f32.sub (f32.convert_i32_s (local.get $y)) (local.get $cy)))
    (local.set $x (i32.const 0))
    (loop $cols
      (local.set $dx (f32.sub (f32.convert_i32_s (local.get $x)) (local.get $cx)))
      (i32.store offset=0x120000 (local.get $p)
        (call $tunnel_shade
          ;; u = scale / (sqrt(dx*dx + dy*dy) + soft) + adv
          (f32.add (f32.div (local.get $scale)
                            (f32.add (f32.sqrt (f32.add (f32.mul (local.get $dx) (local.get $dx))
                                                        (f32.mul (local.get $dy) (local.get $dy))))
                                     (local.get $soft)))
                   (local.get $adv))
          ;; v = atan2(dy, dx) in turns: the port's own series, per pixel
          (call $angle_turns (local.get $dy) (local.get $dx))
          (local.get $spin)))
      (local.set $p (i32.add (local.get $p) (i32.const 4)))
      (local.set $x (i32.add (local.get $x) (i32.const 1)))
      (br_if $cols (i32.lt_s (local.get $x) (global.get $W))))
    (local.set $y (i32.add (local.get $y) (i32.const 1)))
    (br_if $rows (i32.lt_s (local.get $y) (global.get $H))))
  ;; @end
  )

(func $tunnel_render (param $tm f32)
  (if (i32.eq (global.get $rung) (i32.const 1))
    (then (call $tunnel_draw_direct (local.get $tm)))
    (else (call $tunnel_draw (local.get $tm)))))
