//! The babeltro effects in Rust, built as a WebAssembly module for the
//! browser lab. It exports the three functions every port exports (see
//! spec/ABI.md): `bb_init` allocates the framebuffer, `bb_start` begins a
//! scene from a clean state, `bb_render` draws one frame of it. One thread,
//! the effect's pixels and nothing else.
//!
//! ```sh
//! cargo build --release --target wasm32-unknown-unknown
//! ```

mod canvas;
mod fmath;
mod fx;
mod palette;

use std::cell::RefCell;

use canvas::Frame;
use fx::{Effect, State};

/// Everything the module remembers between calls from the host.
struct Lab {
    fb: Frame,
    effect: Option<Box<dyn Effect>>,
}

// The host calls in from a single thread, but Rust does not take that on
// trust: a plain `static` cannot be mutated, and `static mut` makes every
// access `unsafe` (edition 2024 even refuses to take a reference to one).
// `thread_local!` plus `RefCell` is the safe idiom for "one global, one
// thread": on wasm32-unknown-unknown without the atomics feature the
// thread-local is an ordinary static, and the `RefCell` costs one borrow-flag
// check per call — three calls a frame, against a million pixels.
thread_local! {
    static LAB: RefCell<Option<Lab>> = const { RefCell::new(None) };
}

/// Allocates a `w×h` framebuffer and returns its address in linear memory.
/// The host reads the pixels from there after every `bb_render`.
#[unsafe(no_mangle)]
pub extern "C" fn bb_init(w: i32, h: i32) -> i32 {
    let fb = Frame::new(w as usize, h as usize);
    LAB.with_borrow_mut(|lab| {
        // keep a running scene, resized to the new frame
        let mut effect = lab.take().and_then(|old| old.effect);
        if let Some(e) = effect.as_mut() {
            e.resize(fb.w, fb.h);
        }
        let lab = lab.insert(Lab { fb, effect });
        // wasm32 addresses are 32 bits wide: the cast is lossless
        lab.fb.pix.as_mut_ptr() as i32
    })
}

/// Begins `scene` from a fresh effect, so stateful scenes (the fire, the
/// starfield) replay the same history in every language.
#[unsafe(no_mangle)]
pub extern "C" fn bb_start(scene: i32) {
    LAB.with_borrow_mut(|lab| {
        let lab = lab
            .as_mut()
            .expect("bb_init must be called before bb_start");
        let mut effect = fx::new_effect(scene);
        effect.resize(lab.fb.w, lab.fb.h);
        lab.effect = Some(effect);
    });
}

/// Draws frame `n` (n ≥ 1) of the current scene. Time is derived from `n`
/// at a fixed 60 Hz step, never from a clock, so a frame number names the
/// same image everywhere.
#[unsafe(no_mangle)]
pub extern "C" fn bb_render(n: i32) {
    LAB.with_borrow_mut(|lab| {
        let Some(Lab {
            fb,
            effect: Some(effect),
        }) = lab.as_mut()
        else {
            return;
        };
        let t = f64::from(n) / 60.0;
        let s = State {
            t,
            beat: t,
            dt: 1.0 / 60.0,
            frame: n as u64,
        };
        effect.prepare(&s);
        effect.draw(fb);
    });
}
