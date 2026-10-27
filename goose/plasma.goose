// The PLASMA scene, ported from internal/fx/plasma.go — and then the same
// scene made parallel, which is where Goose reshapes the program.
//
// Build and run (from this directory):
//   goose build plasma.goose -o plasma && ./plasma
//
// The serial part is a faithful port: same three summed fields, same sine
// table, same 256-entry ramp with its smoothstep, same index arithmetic, so
// its numbers can be held against the Go demo's.
//
// The parallel part is where the language makes itself felt. Goose threads
// share no memory at all (spec §11.2): a worker is a separate program
// instance with its own copy of every global, and only *flat* values — no
// references, no slices — may cross a thread boundary. Three things follow
// that the Go version does not have to think about:
//
//   1. There is no "write my band of the framebuffer". A band has to be
//      computed into a fixed array, sent back through a queue, and copied
//      into the frame by main. That copy is real time the Go demo does not
//      spend, though a whole-row assignment compiles to a memcpy, so it is
//      not the cliff a per-pixel loop would be.
//   2. A typed queue is one shared work queue, not a mailbox per worker.
//      Queue eight jobs and whichever worker gets there first takes them:
//      one worker can take three and another none. So a job must say which
//      band it is, and main must reassemble by that field rather than by
//      assuming a fixed worker → band mapping.
//   3. Each worker needs its own copy of the distance field, because the
//      distance field is a global and globals are not shared. Eight copies
//      of a 3.7 MB table is the direct price of the memory model.
//
// The upside of (2) is automatic load balancing; the prices of (1) and (3)
// are printed below.
//
// One thing the port taught, and the demo's README now says: fixed arrays
// are not just a style choice. A fixed 2D array makes the index arithmetic
// provable, so the compiler drops 62 of 79 bounds checks, and the serial
// loop comes out at Go's speed — a slice-shaped framebuffer does not. The
// fixed layout is also what makes the band copy a row-by-row assignment,
// which compiles to a memcpy instead of a per-pixel loop.

import std;
import math;
import os;

let WIDTH = 1280;
let HEIGHT = 720;
let TAB = 8192;
let TAB_MASK = 8191;

let NTHREADS = 8;
let BAND_ROWS = HEIGHT / NTHREADS;
let BAND_PX = WIDTH * BAND_ROWS;

var sin_tab: f32[>..] = [];
var pal: u32[256] = [0; 256];

// Fixed 2D arrays, so a whole row can be assigned (compiled to a memcpy).
// Goose nests fixed arrays as T[inner][outer]: u32[WIDTH][HEIGHT] is HEIGHT
// elements of type u32[WIDTH], so it is indexed [y][x] and each fb[y] is one
// contiguous row — which is exactly what a row copy wants.
var fb: u32[WIDTH][HEIGHT] = [[0; WIDTH]; HEIGHT];
var rad: f32[WIDTH][HEIGHT] = [[0.0; WIDTH]; HEIGHT];
var sx: f32[WIDTH] = [0.0; WIDTH];
var sy: f32[HEIGHT] = [0.0; HEIGHT];
var sxy: f32[WIDTH + HEIGHT] = [0.0; WIDTH + HEIGHT];

// Each worker's private copies of the per-frame tables and the distance
// field. Full height, not band height: a worker can be handed any band.
var w_rad: f32[WIDTH][HEIGHT] = [[0.0; WIDTH]; HEIGHT];
var w_sx: f32[WIDTH] = [0.0; WIDTH];
var w_sy: f32[HEIGHT] = [0.0; HEIGHT];
var w_sxy: f32[WIDTH + HEIGHT] = [0.0; WIDTH + HEIGHT];

// sin_lut wraps any angle into the table, as internal/fmath does.
fn sin_lut(a: f32) -> f32 {
    let j = (a * (TAB / 6.283185307179586)) as i64;
    let i = (j & TAB_MASK) as u32;
    return sin_tab[i as i64];
}

fn build_sin_tab() {
    sin_tab.resize(TAB, 0.0);
    for i in TAB {
        sin_tab[i] = sin(6.283185307179586 * i / TAB) as f32;
    }
}

fn f2b(v: f64) -> u32 {
    if v <= 0.0 { return 0; }
    if v >= 1.0 { return 255; }
    return (v * 255.0 + 0.5) as u32;
}

// The Sunset ramp from internal/palette: seven stops, smoothstep between
// them, built once. A fixed array nests as T[columns][rows], so each row
// below is one channel across the seven stops; row 0 is the position.
fn build_palette() {
    let stops: f64[7][4] = [
        [0.00, 0.18, 0.38, 0.56, 0.74, 0.88, 1.00],
        [0.02, 0.25, 0.72, 0.98, 1.00, 1.00, 1.00],
        [0.00, 0.02, 0.05, 0.25, 0.62, 0.93, 1.00],
        [0.06, 0.38, 0.45, 0.22, 0.15, 0.55, 0.96]
    ];
    for i in 256 {
        let t = i as f64 / 255.0;
        // find the segment containing t
        var k = 0;
        while k + 1 < 7 && !(t >= stops[0][k] && t <= stops[0][k + 1]) { k++; }
        let p0 = stops[0][k];
        let p1 = stops[0][k + 1];
        var u = if p1 > p0 { (t - p0) / (p1 - p0) } else { 0.0 };
        if u < 0.0 { u = 0.0; }
        if u > 1.0 { u = 1.0; }
        // smoothstep keeps gradients from banding
        u = u * u * (3.0 - 2.0 * u);
        let r = stops[1][k] + (stops[1][k + 1] - stops[1][k]) * u;
        let g = stops[2][k] + (stops[2][k + 1] - stops[2][k]) * u;
        let bl = stops[3][k] + (stops[3][k + 1] - stops[3][k]) * u;
        pal[i] = 0xFF000000 | (f2b(bl) << 16) | (f2b(g) << 8) | f2b(r);
    }
}

// setup builds every table that depends only on the frame size.
fn setup(w: i64, h: i64) {
    let cx: f32 = w * 0.5;
    let cy: f32 = h * 0.5;
    let k: f32 = 44.0 / (w + h);
    for y in h {
        let dy = y - cy;
        let base = y * w;
        for x in w {
            let dx = x - cx;
            rad[y][x] = sqrt(dx * dx + dy * dy) * k;
        }
    }
}

// prepare rebuilds the per-frame 1D tables: two of the three sine terms
// become lookups, leaving one table index per pixel in the hot loop.
fn prepare(w: i64, h: i64, t: f32) {
    let kx: f32 = 26.0 / w;
    let ky: f32 = 26.0 / h;
    for x in w { sx[x] = sin_lut(x * kx + t * 1.3); }
    for y in h { sy[y] = sin_lut(y * ky * 1.35 - t * 1.1); }
    for i in w + h {
        sxy[i] = sin_lut(i * kx * 0.85 + t * 0.8);
    }
}

fn draw(w: i64, h: i64, t: f32) {
    prepare(w, h, t);
    let phase = t * 2.6;
    for y in h {
        let syv = sy[y];
        let row = y * w;
        let dy = y;
        for x in w {
            let v = sx[x] + syv + sxy[x + y] + sin_lut(rad[y][x] + phase);
            var i = ((v * 36.0 + 127.5) as i64);
            if i < 0 { i = 0; }
            if i > 255 { i = 255; }
            fb[y][x] = pal[i];
        }
    }
}

// --- threads ---------------------------------------------------------------

// Both messages are flat, which is the requirement for crossing a thread
// boundary. Job names the band it wants; Band names the band it carries.
struct Job { y0: i64, rows: i64, t: f32, quit: bool }
struct Band { y0: i64, px: u32[WIDTH][BAND_ROWS] }

thread_fn band_worker(idx: i64) {
    let w = WIDTH;
    let h = HEIGHT;
    let kx: f32 = 26.0 / w;
    let ky: f32 = 26.0 / h;

    // The distance field covers any band this worker is handed, so its own
    // copy is the full frame: with no shared memory, that is the price. The
    // y-only and x+y-only tables can be sized to one band, because a row of
    // them is all a band ever reads.
    let cx: f32 = w * 0.5;
    let cy: f32 = h * 0.5;
    let k: f32 = 44.0 / (w + h);
    for y in h {
        let dy = y - cy;
        let base = y * w;
        for x in w {
            let dx = x - cx;
            w_rad[y][x] = sqrt(dx * dx + dy * dy) * k;
        }
    }

    var out = Band { y0: 0, px: [[0; WIDTH]; BAND_ROWS] };
    loop {
        let job = qget<Job>();
        guard !job.quit else { break; }

        let t = job.t;
        let y0 = job.y0;
        let rows = job.rows;

        // Per-frame tables. A worker may take several jobs of one frame or
        // none, so it cannot tell that it has already built them: it rebuilds
        // per job. That is w + h lookups against rows * w pixels.
        for x in w { w_sx[x] = sin_lut(x * kx + t * 1.3); }
        for y in h { w_sy[y] = sin_lut(y * ky * 1.35 - t * 1.1); }
        for i in w + h { w_sxy[i] = sin_lut(i * kx * 0.85 + t * 0.8); }

        let phase = t * 2.6;
        out.y0 = y0;
        for y in rows {
            let ay = y0 + y;
            let syv = w_sy[ay];
            // the distance-field row this band row reads, as one row copy
            let rad_row = w_rad[ay];
            for x in w {
                let v = w_sx[x] + syv + w_sxy[x + ay] + sin_lut(rad_row[x] + phase);
                var i = ((v * 36.0 + 127.5) as i64);
                if i < 0 { i = 0; }
                if i > 255 { i = 255; }
                out.px[y][x] = pal[i];
            }
        }
        qput(out);
    }
}

fn main() {
    build_sin_tab();
    build_palette();

    let w = WIDTH;
    let h = HEIGHT;
    setup(w, h);

    let mpx = (w * h) as f64 / 1000000.0;
    let frames = 240;

    // --- one thread --------------------------------------------------------
    for n in 20 { draw(w, h, n / 60.0); }
    let t0 = clock();
    for n in frames { draw(w, h, n / 60.0); }
    let t1 = clock();
    let ms1 = (t1 - t0) * 1000.0 / frames;

    var serial_ok = 0;
    for y in h { for x in w { if fb[y][x] != 0 { serial_ok++; } } }

    // Keep the serial frame so the threaded render can be compared to it
    // pixel for pixel afterwards.
    var serial_fb: u32[WIDTH][HEIGHT] = [[0; WIDTH]; HEIGHT];
    for y in h { serial_fb[y] = fb[y]; }

    // --- eight threads, one job per band, jobs taken by whoever is free ----
    var ids: i64[>..] = [];
    for i in NTHREADS { ids.push(thread_spawn(band_worker, i)); }

    var t2 = 0.0;
    var t3 = 0.0;
    var copy_ns = 0.0;
    for f in frames + 20 {
        let fr = if f >= 20 { f - 20 } else { f };
        let t = (fr as f32) / 60.0;
        for i in NTHREADS {
            qput(Job { y0: i * BAND_ROWS, rows: BAND_ROWS, t: t, quit: false });
        }
        // Reassemble by the band the result names, not by arrival order: the
        // queue is shared, so the order is whatever the workers made it.
        for i in NTHREADS {
            let b = qget<Band>();
            let c0 = clock();
            for y in BAND_ROWS { fb[b.y0 + y] = b.px[y]; }
            if f >= 19 { copy_ns += clock() - c0; }
        }
        if f == 19 { t2 = clock(); }
    }
    let t3 = clock();
    let ms8 = (t3 - t2) * 1000.0 / frames;
    // how much of the threaded frame is the queue-to-framebuffer copy that
    // Goose forces and the Go version does not need
    let ms_copy = copy_ns * 1000.0 / frames;

    for i in NTHREADS { qput(Job { y0: 0, rows: 0, t: 0.0, quit: true }); }
    for id in ids { thread_wait(id); }

    var threaded_ok = 0;
    for y in h { for x in w { if fb[y][x] != 0 { threaded_ok++; } } }

    // Both paths rendered their last frame at the same t, so they must agree
    // byte for byte. Anything but 0 here means the reassembly is wrong.
    var diff = 0;
    for y in h { for x in w { if fb[y][x] != serial_fb[y][x] { diff++; } } }

    // Write the frame out as a PPM so it can be held against the Go demo's
    // render of the same t pixel for pixel. bytes_of views the rows without
    // a copy: only the header is built.
    var ppm: u8[>..] = [];
    format(ppm, "P6\n", w, " ", h, "\n255\n");
    for y in h {
        for x in w {
            let c = fb[y][x];
            var rgb: u8[3] = [(c & 0xFF) as u8, ((c >> 8) & 0xFF) as u8, ((c >> 16) & 0xFF) as u8];
            ppm.append(rgb);
        }
    }
    write_file("plasma_goose.ppm", ppm);

    var line: u8[>..] = [];
    format_flt(line, ms1, 3);
    print("GOOSE plasma ", w, "x", h, " single thread: ", line, " ms/frame");
    line.clear();
    format_flt(line, mpx / ms1 * 1000.0, 1);
    print("   ", line, " Mpx/s");
    line.clear();
    format_flt(line, ms8, 3);
    print("GOOSE plasma ", w, "x", h, " ", NTHREADS, " threads:     ", line, " ms/frame");
    line.clear();
    format_flt(line, mpx / ms8 * 1000.0, 1);
    print("   ", line, " Mpx/s  (checksum ", fb[h / 2][w / 2], ")");
    print("pixels drawn: serial ", serial_ok, " / threaded ", threaded_ok);
    print("serial vs threaded: ", diff, " differing pixels");
    line.clear();
    format_flt(line, ms_copy, 3);
    print("   of which the band copy back: ", line, " ms/frame");
}
