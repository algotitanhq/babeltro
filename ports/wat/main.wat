;; main: the start function and the four exports the lab calls (spec/ABI.md)

;; The start function runs once, when the module is instantiated, before the
;; host can call anything: the place for tables that never change.
(func $init
  (call $build_sine_tables)
  (call $build_atan_series)
  (call $build_palettes))
(start $init)

;; bb_init lays out a w*h framebuffer at 0x120000, with the scratch tables
;; after it, and grows the memory to fit. memory.grow counts 64 KiB pages
;; and returns -1 when the host refuses; there is nothing sensible to draw
;; then, so we trap.
(func (export "bb_init") (param $w i32) (param $h i32) (result i32)
  (local $wh i32) (local $need i32) (local $pages i32)
  (global.set $W (local.get $w))
  (global.set $H (local.get $h))
  (local.set $wh (i32.mul (local.get $w) (local.get $h)))
  ;; scratch starts after the framebuffer, on a 16-byte boundary
  (global.set $SCRATCH
    (i32.and (i32.add (i32.add (i32.const 0x120000) (i32.shl (local.get $wh) (i32.const 2)))
                      (i32.const 15))
             (i32.const -16)))
  ;; the largest scene tables: the tunnel's two w*h f32 arrays, the
  ;; plasma's one w*h array plus 2*(w+h) row and column entries, or the
  ;; starfield's backdrop plus 56 KiB of stars: 64 KiB of slack covers it
  (local.set $need
    (i32.add (global.get $SCRATCH)
             (i32.add (i32.shl (local.get $wh) (i32.const 3))
                      (i32.add (i32.shl (i32.add (local.get $w) (local.get $h)) (i32.const 3))
                               (i32.const 0x10000)))))
  (local.set $pages (i32.shr_u (i32.add (local.get $need) (i32.const 0xFFFF)) (i32.const 16)))
  (if (i32.gt_u (local.get $pages) (memory.size))
    (then
      (if (i32.eq (memory.grow (i32.sub (local.get $pages) (memory.size))) (i32.const -1))
        (then unreachable))))
  (i32.const 0x120000))

;; bb_start begins a scene from a fresh state. br_table is wasm's switch: it
;; jumps out of the nth enclosing block, so the blocks are nested in reverse
;; and each case's code sits just after its block closes. Any number past
;; the last scene is the default label, the finale, as in Go.
(func (export "bb_start") (param $scene i32)
  (global.set $scene (local.get $scene))
  (global.set $rung (i32.const 0))
  (block $done
    (block $finale
      (block $mandelbrot
        (block $fire
          (block $grid
            (block $metaballs
              (block $rotozoom
                (block $plasma
                  (block $tunnel
                    (block $starfield
                      (br_table $starfield $tunnel $plasma $rotozoom $metaballs $grid $fire
                                $mandelbrot $finale (local.get $scene)))
                    (call $starfield_start) (br $done))
                  (call $tunnel_start) (br $done))
                (call $plasma_start) (br $done))
              (call $rotozoom_start) (br $done))
            (br $done))                            ;; metaballs keeps no tables
          (br $done))                              ;; neither does the grid
        (call $fire_start) (br $done))
      (call $mandelbrot_start) (br $done))
    (call $finale_start)))

;; bb_step picks the rung of the scene's ladder; 0 is the optimised default.
;; Scenes without a ladder never read it.
(func (export "bb_step") (param $n i32)
  (global.set $rung (local.get $n)))

;; bb_render draws frame n. Time is n/60 in f64; the scenes that work in f32
;; take float32(t), rounded once by f32.demote_f64, exactly as Go's
;; float32(s.Beat). The fire only wants the frame number.
(func (export "bb_render") (param $n i32)
  (local $t f64)
  (local.set $t (f64.div (f64.convert_i32_s (local.get $n)) (f64.const 60)))
  (block $done
    (block $finale
      (block $mandelbrot
        (block $fire
          (block $grid
            (block $metaballs
              (block $rotozoom
                (block $plasma
                  (block $tunnel
                    (block $starfield
                      (br_table $starfield $tunnel $plasma $rotozoom $metaballs $grid $fire
                                $mandelbrot $finale (global.get $scene)))
                    (call $starfield_render (local.get $t)) (br $done))
                  (call $tunnel_render (f32.demote_f64 (local.get $t))) (br $done))
                (call $plasma_render (f32.demote_f64 (local.get $t))) (br $done))
              (call $rotozoom_render (f32.demote_f64 (local.get $t))) (br $done))
            (call $metaballs_render (f32.demote_f64 (local.get $t))) (br $done))
          (call $grid_render (f32.demote_f64 (local.get $t))) (br $done))
        (call $fire_render (local.get $n)) (br $done))
      (call $mandelbrot_render (local.get $t)) (br $done))
    (call $finale_render (local.get $t))))
