// Command goose runs the demo: a software-rendered demoscene piece whose
// subject is the speed of the language it is written in.
package main

import (
	"flag"
	"fmt"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"runtime"
	"time"
	"unsafe"

	"rosette/internal/canvas"
	"rosette/internal/engine"
	"rosette/internal/fx"
	"rosette/internal/glc"
	"rosette/internal/glfwc"
)

func main() {
	runtime.LockOSThread()

	var (
		wFlag     = flag.Int("w", 1280, "window width")
		hFlag     = flag.Int("h", 720, "window height")
		fsFlag    = flag.Bool("fs", false, "start fullscreen")
		vsyncFlag = flag.Bool("vsync", true, "lock to the display refresh rate")
		sceneFlag = flag.Int("scene", 0, "start at scene index (0-based)")
		listFlag  = flag.Bool("list", false, "list scenes and exit")
		workers   = flag.Int("workers", runtime.NumCPU(), "render goroutines")
		dumpFlag  = flag.String("dump", "", "render to PNG files in this directory instead of opening a window")
		atFlag    = flag.Float64("at", 5.0, "with -dump: seconds into each scene to capture")
		benchFlag = flag.Bool("bench", false, "measure every effect and print a table")
		statsFlag = flag.Bool("stats", false, "print live measurements once a second")
		durFlag   = flag.Float64("dur", 0, "quit after this many seconds (0 = run forever)")
		benchFor  = flag.Int("bench-frames", 240, "with -bench: frames measured per effect")
	)
	flag.Parse()

	if *listFlag {
		for i, s := range buildScenes() {
			fmt.Printf("%2d  %-12s %5.1fs\n", i, s.Name, s.Dur)
		}
		return
	}

	if *benchFlag {
		runBench(*wFlag, *hFlag, *workers, *benchFor)
		return
	}

	if *dumpFlag != "" {
		dumpAll(*dumpFlag, *wFlag, *hFlag, *atFlag, *workers)
		return
	}

	if err := glfwc.Init(); err != nil {
		fail(err)
	}
	defer glfwc.Terminate()

	glfwc.WindowHint(glfwc.CocoaRetinaFramebuf, 1)
	glfwc.WindowHint(glfwc.Visible, 1)
	glfwc.WindowHint(glfwc.Resizable, 1)

	win, err := glfwc.CreateWindow(*wFlag, *hFlag, "GOOSE — every pixel is Go")
	if err != nil {
		fail(err)
	}
	defer glfwc.DestroyWindow(win)

	glfwc.MakeContextCurrent(win)
	if *vsyncFlag {
		glfwc.SwapInterval(1)
	} else {
		glfwc.SwapInterval(0)
	}
	glfwc.FocusWindow(win)

	fbw, fbh := glfwc.FramebufferSize(win)
	tex := glc.InitBlitState(fbw, fbh)
	fb := canvas.New(fbw, fbh)

	refresh := glfwc.RefreshRate()
	if refresh <= 0 {
		refresh = 60
	}
	budget := 1000.0 / float64(refresh)

	eng := engine.New(fb, buildScenes(), *workers, budget)
	if *sceneFlag > 0 {
		eng.Jump(0, *sceneFlag)
	}
	if *fsFlag {
		glfwc.SetFullscreen(win, true, *wFlag, *hFlag)
	}

	fmt.Printf("goose: %dx%d, %d workers, budget %.2f ms (%d Hz)\n",
		fbw, fbh, eng.Workers(), budget, refresh)
	fmt.Println("keys: ESC quit · H hud · S next scene · F fullscreen")

	if *statsFlag {
		fmt.Println("     t     fps   cpu ms   budget   scene")
	}

	start := time.Now()
	prev := start
	keys := &keyLatch{}

	for !glfwc.WindowShouldClose(win) {
		now := time.Now()
		dt := now.Sub(prev).Seconds()
		prev = now
		t := now.Sub(start).Seconds()

		glfwc.PollEvents()

		// window / retina size can change at any time
		nw, nh := glfwc.FramebufferSize(win)
		if nw != fbw || nh != fbh {
			if nw <= 0 || nh <= 0 {
				// minimised: do not upload a zero-sized texture
				time.Sleep(16 * time.Millisecond)
				continue
			}
			fbw, fbh = nw, nh
			tex = glc.InitBlitState(fbw, fbh)
			eng.Resize(fbw, fbh)
		}

		if keys.pressed(win, glfwc.KeyEscape) {
			glfwc.SetWindowShouldClose(win, true)
		}
		if keys.pressed(win, glfwc.KeyH) {
			eng.HUD.Visible = !eng.HUD.Visible
		}
		if keys.pressed(win, glfwc.KeyS) || keys.pressed(win, glfwc.KeyRight) {
			eng.Next(t)
		}
		if keys.pressed(win, glfwc.KeyF) || keys.pressed(win, glfwc.KeyF1) {
			keys.fullscreen = !keys.fullscreen
			glfwc.SetFullscreen(win, keys.fullscreen, *wFlag, *hFlag)
		}

		eng.Step(t, dt)

		glc.Viewport(0, 0, fbw, fbh)
		glc.Clear(glc.ColorBufferBit)
		glc.DrawFullscreenRGBA(tex, fbw, fbh, unsafe.Pointer(&fb.Pix[0]))
		glfwc.SwapBuffers(win)

		if *statsFlag && int(t) != int(t-dt) {
			fmt.Printf("%6.1fs  %5.1f  %7.2f   %5.2f   %s\n", t, eng.FPS(), eng.CPUMs(), budget, eng.SceneName())
		}
		if *durFlag > 0 && t > *durFlag {
			glfwc.SetWindowShouldClose(win, true)
		}
	}
}

func buildScenes() []engine.Scene {
	return []engine.Scene{
		{Name: "STARFIELD", Eff: fx.NewStarfield(), Dur: 9},
		{Name: "TUNNEL", Eff: fx.NewTunnel(), Dur: 11},
		{Name: "PLASMA", Eff: fx.NewPlasma(), Dur: 10},
		{Name: "ROTOZOOM", Eff: fx.NewRotozoom(), Dur: 9},
		{Name: "METABALLS", Eff: fx.NewMetaballs(), Dur: 9},
		{Name: "GRID", Eff: fx.NewGrid(), Dur: 10},
		{Name: "FIRE", Eff: fx.NewFire(), Dur: 9},
		{Name: "MANDELBROT", Eff: fx.NewMandelbrot(), Dur: 12},
		{Name: "FINALE", Eff: fx.NewFinale(), Dur: 14},
	}
}

// keyLatch turns held keys into single presses.
type keyLatch struct {
	state      map[int]bool
	fullscreen bool
}

func (k *keyLatch) pressed(win *glfwc.Window, key int) bool {
	if k.state == nil {
		k.state = make(map[int]bool)
	}
	down := glfwc.GetKey(win, key) == glfwc.PressKey
	was := k.state[key]
	k.state[key] = down
	return down && !was
}

// dumpAll renders every scene headlessly and writes one PNG per scene. No
// window, no OpenGL: the whole engine is just functions over a framebuffer,
// which is exactly the point of keeping the renderer independent of the
// presenter.
// runBench renders every effect headlessly and prints the cost of one frame.
func runBench(w, h, workers, frames int) {
	fb := canvas.New(w, h)
	eng := engine.New(fb, buildScenes(), workers, 16.67)
	res := eng.Bench(frames)

	fmt.Printf("goose bench \u2014 %dx%d, %d workers, %d frames each\n\n", w, h, workers, frames)
	fmt.Printf("%-12s %10s %10s %12s %8s\n", "SCENE", "MEDIAN", "BEST", "MEGAPIX/S", "FRAMES")
	fmt.Printf("%-12s %10s %10s %12s %8s\n", "", "ms", "ms", "", "")
	var total float64
	var worst string
	var worstMS float64
	for _, r := range res {
		fmt.Printf("%-12s %10.3f %10.3f %12.1f %8d\n", r.Name, r.Median, r.Min, r.Mpixels, r.Frames)
		total += r.Median
		if r.Median > worstMS {
			worstMS = r.Median
			worst = r.Name
		}
	}
	fmt.Printf("\n%-12s %10.3f\n", "SUM", total)
	fmt.Printf("%-12s %10.3f  (%s)\n", "SLOWEST", worstMS, worst)
}

func dumpAll(dir string, w, h int, at float64, workers int) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		fail(err)
	}
	scenes := buildScenes()
	for i := range scenes {
		fb := canvas.New(w, h)
		eng := engine.New(fb, buildScenes(), workers, 16.67)
		eng.Jump(0, i)
		// simulate from t=0 so stateful effects (fire) settle naturally
		dt := 1.0 / 60
		var t float64
		for t < at {
			t += dt
			eng.Step(t, dt)
		}
		path := filepath.Join(dir, fmt.Sprintf("%02d_%s.png", i, scenes[i].Name))
		if err := writePNG(path, fb); err != nil {
			fail(err)
		}
		fmt.Printf("%-14s -> %s\n", scenes[i].Name, path)
	}
}

func writePNG(path string, fb *canvas.FB) error {
	img := image.NewRGBA(image.Rect(0, 0, fb.W, fb.H))
	for i, p := range fb.Pix {
		o := i * 4
		img.Pix[o+0] = uint8(p)
		img.Pix[o+1] = uint8(p >> 8)
		img.Pix[o+2] = uint8(p >> 16)
		img.Pix[o+3] = 255
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return png.Encode(f, img)
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "goose:", err)
	os.Exit(1)
}
