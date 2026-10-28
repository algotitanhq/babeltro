//! The numeric shortcuts every effect leans on: a sine table and the
//! xorshift32 generator. Calling `sin` a million times per frame is the
//! difference between 20 ms and 1 ms, so the hot loops use table lookups.

use std::f32::consts::TAU;
use std::sync::LazyLock;

const TAB_BITS: u32 = 13;
pub const TAB_SIZE: usize = 1 << TAB_BITS;
const TAB_MASK: i64 = TAB_SIZE as i64 - 1;
/// Table entries per radian, 8192/2π rounded once to f32 (the same bits as
/// Go's untyped-constant arithmetic gives).
const STEPS_PER_RADIAN: f32 = (TAB_SIZE as f64 / std::f64::consts::TAU) as f32;

/// One period of sine and cosine, sampled `TAB_SIZE` times.
pub struct SineTable {
    sin: [f32; TAB_SIZE],
    cos: [f32; TAB_SIZE],
}

static TABLE: LazyLock<SineTable> = LazyLock::new(|| {
    let mut tab = SineTable {
        sin: [0.0; TAB_SIZE],
        cos: [0.0; TAB_SIZE],
    };
    for (i, (s, c)) in tab.sin.iter_mut().zip(&mut tab.cos).enumerate() {
        let a = 2.0 * std::f64::consts::PI * i as f64 / TAB_SIZE as f64;
        *s = a.sin() as f32;
        *c = a.cos() as f32;
    }
    tab
});

/// The shared table. Hot loops fetch it once and call its methods, so the
/// lazy-initialisation check stays out of the per-pixel path.
pub fn table() -> &'static SineTable {
    &TABLE
}

impl SineTable {
    /// Truncates toward zero, as Go's `int()` does, then wraps into the
    /// table. `as i64` saturates instead of wrapping, but the arguments here
    /// stay many orders of magnitude inside the i64 range, where both agree.
    /// The mask proves the index is in bounds, so the lookup has no check.
    fn index(steps: f32) -> usize {
        (steps as i64 & TAB_MASK) as usize
    }

    /// sin(a), a in radians.
    pub fn sin(&self, a: f32) -> f32 {
        self.sin[Self::index(a * STEPS_PER_RADIAN)]
    }

    /// cos(a), a in radians.
    pub fn cos(&self, a: f32) -> f32 {
        self.cos[Self::index(a * STEPS_PER_RADIAN)]
    }

    /// sin(2πt), t in turns.
    pub fn sin01(&self, t: f32) -> f32 {
        self.sin[Self::index(t * TAB_SIZE as f32)]
    }
}

/// atan2(y, x) as a fraction of a full turn, in [0, 1).
pub fn atan2_turns(y: f32, x: f32) -> f32 {
    let a = f64::from(y).atan2(f64::from(x)) as f32;
    a / TAU + 0.5
}

/// The turn fraction of atan2 for every pixel of a `w×h` grid, measured from
/// its centre. Built once per resize, used by the tunnel.
pub fn atan2_table(w: usize, h: usize) -> Vec<f32> {
    let (cx, cy) = (w as f32 / 2.0, h as f32 / 2.0);
    (0..h)
        .flat_map(|y| {
            let dy = y as f32 - cy;
            (0..w).map(move |x| atan2_turns(dy, x as f32 - cx))
        })
        .collect()
}

/// `scale / (r + softness)` for every pixel of a `w×h` grid, r being the
/// distance to its centre. The softness term tames the singularity at the
/// centre, which would otherwise turn into aliasing noise.
pub fn dist_inv_table(w: usize, h: usize, scale: f32, softness: f32) -> Vec<f32> {
    let (cx, cy) = (w as f32 / 2.0, h as f32 / 2.0);
    (0..h)
        .flat_map(|y| {
            let dy = y as f32 - cy;
            (0..w).map(move |x| {
                let dx = x as f32 - cx;
                // f32 sqrt is correctly rounded, exactly like Go's
                // float32(math.Sqrt(float64(x)))
                scale / ((dx * dx + dy * dy).sqrt() + softness)
            })
        })
        .collect()
}

/// A xorshift32 generator. Every port reproduces the same sequence bit for
/// bit: three shifts and three xors are the same in any language. Shifting
/// bits out of a `u32` is not an overflow in Rust, so no `wrapping_*` is
/// needed here.
#[derive(Clone, Debug)]
pub struct Rng(u32);

impl Rng {
    /// The seed must not be zero.
    pub const fn new(seed: u32) -> Self {
        Rng(seed)
    }

    /// Advances the generator and returns the new state.
    pub fn next_u32(&mut self) -> u32 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.0 = x;
        x
    }

    /// A number in [0, 1) from the top 24 bits of `next_u32`, so the
    /// conversion to f32 is exact in every language.
    pub fn next_f32(&mut self) -> f32 {
        (self.next_u32() >> 8) as f32 * (1.0 / 16_777_216.0)
    }
}
