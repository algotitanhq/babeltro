//! The effects. Every one of them writes pixels straight into the
//! framebuffer on the CPU; there is no shader anywhere in this demo.

mod finale;
mod fire;
mod grid;
mod mandelbrot;
mod metaballs;
mod plasma;
mod rotozoom;
mod starfield;
mod tunnel;

use crate::canvas::Frame;

/// What an effect knows about time.
pub struct State {
    /// seconds since the demo started
    pub t: f64,
    /// seconds since this scene started
    pub beat: f64,
    /// seconds since the previous frame
    pub dt: f64,
    /// frame counter
    pub frame: u64,
}

/// One scene. The host resizes it once, then for every frame calls `prepare`
/// (per-frame lookup tables and animation state) and `draw` (the pixels).
pub trait Effect {
    /// Rebuilds any tables tied to the resolution.
    fn resize(&mut self, w: usize, h: usize);
    /// Runs once per frame before `draw`.
    fn prepare(&mut self, s: &State);
    /// Renders the whole frame.
    fn draw(&mut self, fb: &mut Frame);
}

/// The effect for scene number `scene`, in playback order.
pub fn new_effect(scene: i32) -> Box<dyn Effect> {
    match scene {
        0 => Box::new(starfield::Starfield::new()),
        1 => Box::new(tunnel::Tunnel::new()),
        2 => Box::new(plasma::Plasma::new()),
        3 => Box::new(rotozoom::Rotozoom::new()),
        4 => Box::new(metaballs::Metaballs::new()),
        5 => Box::new(grid::Grid::new()),
        6 => Box::new(fire::Fire::new()),
        7 => Box::new(mandelbrot::Mandelbrot::new()),
        _ => Box::new(finale::Finale::new()),
    }
}
