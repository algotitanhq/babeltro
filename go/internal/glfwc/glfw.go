// Package glfwc is a deliberately tiny binding to GLFW: just enough to open
// one window, pump its events and push frames at it. Keeping it in-tree means
// the demo has no Go-level dependency outside the standard library, and the
// cgo flags are ours (Homebrew's GLFW lives outside the default search path).
package glfwc

/*
#cgo pkg-config: glfw3
#cgo darwin LDFLAGS: -framework Cocoa
#define GLFW_INCLUDE_NONE
#include <stdlib.h>
#include <GLFW/glfw3.h>

// Defined in activate.m (Objective-C lives in its own translation unit).
void goose_activate(void);

static int goose_get_window_size(GLFWwindow *w, int *cw, int *ch) {
	glfwGetWindowSize(w, cw, ch);
	return 0;
}

static void goose_fullscreen(GLFWwindow *w, int on, int ww, int wh) {
	if (on) {
		GLFWmonitor *m = glfwGetPrimaryMonitor();
		const GLFWvidmode *vm = glfwGetVideoMode(m);
		glfwSetWindowMonitor(w, m, 0, 0, vm->width, vm->height, vm->refreshRate);
	} else {
		glfwSetWindowMonitor(w, NULL, 80, 80, ww, wh, GLFW_DONT_CARE);
	}
}
*/
import "C"

import (
	"errors"
	"unsafe"
)

// Window is an opaque GLFW window handle.
type Window = C.GLFWwindow

// Window hints we use.
const (
	Visible             = C.GLFW_VISIBLE
	Resizable           = C.GLFW_RESIZABLE
	Decorated           = C.GLFW_DECORATED
	Floating            = C.GLFW_FLOATING
	ScaleToMonitor      = C.GLFW_SCALE_TO_MONITOR
	CocoaRetinaFramebuf = C.GLFW_COCOA_RETINA_FRAMEBUFFER
	Samples             = C.GLFW_SAMPLES
)

// Key codes we use.
const (
	KeyEscape = C.GLFW_KEY_ESCAPE
	KeySpace  = C.GLFW_KEY_SPACE
	KeyF1     = C.GLFW_KEY_F1
	KeyF      = C.GLFW_KEY_F
	KeyH      = C.GLFW_KEY_H
	KeyS      = C.GLFW_KEY_S
	KeyLeft   = C.GLFW_KEY_LEFT
	KeyRight  = C.GLFW_KEY_RIGHT
)

// Press is a key state.
type Press int

const (
	Release  Press = C.GLFW_RELEASE
	PressKey Press = C.GLFW_PRESS
	Repeat   Press = C.GLFW_REPEAT
)

func Init() error {
	if C.glfwInit() != C.GLFW_TRUE {
		return errors.New("glfw: init failed")
	}
	return nil
}

func Terminate() { C.glfwTerminate() }

func WindowHint(hint, value int) {
	C.glfwWindowHint(C.int(hint), C.int(value))
}

// CreateWindow creates a window whose framebuffer is in physical pixels.
func CreateWindow(width, height int, title string) (*C.GLFWwindow, error) {
	ctitle := C.CString(title)
	defer C.free(unsafe.Pointer(ctitle))
	w := C.glfwCreateWindow(C.int(width), C.int(height), ctitle, nil, nil)
	if w == nil {
		return nil, errors.New("glfw: create window failed")
	}
	return w, nil
}

func MakeContextCurrent(w *C.GLFWwindow) { C.glfwMakeContextCurrent(w) }

// SwapInterval sets vsync: 1 = swap every refresh, 0 = uncapped.
func SwapInterval(n int) { C.glfwSwapInterval(C.int(n)) }

func SwapBuffers(w *C.GLFWwindow) { C.glfwSwapBuffers(w) }

func PollEvents() { C.glfwPollEvents() }

func WaitEventsTimeout(seconds float64) { C.glfwWaitEventsTimeout(C.double(seconds)) }

func WindowShouldClose(w *C.GLFWwindow) bool { return C.glfwWindowShouldClose(w) == C.GLFW_TRUE }

func SetWindowShouldClose(w *C.GLFWwindow, v bool) {
	cv := C.GLFW_FALSE
	if v {
		cv = C.GLFW_TRUE
	}
	C.glfwSetWindowShouldClose(w, C.int(cv))
}

// FramebufferSize returns the drawable size in physical pixels (Retina aware).
func FramebufferSize(w *C.GLFWwindow) (int, int) {
	var fw, fh C.int
	C.glfwGetFramebufferSize(w, &fw, &fh)
	return int(fw), int(fh)
}

// WindowSize returns the window size in screen coordinates.
func WindowSize(w *C.GLFWwindow) (int, int) {
	var ww, wh C.int
	C.goose_get_window_size(w, &ww, &wh)
	return int(ww), int(wh)
}

func SetWindowTitle(w *C.GLFWwindow, title string) {
	ctitle := C.CString(title)
	defer C.free(unsafe.Pointer(ctitle))
	C.glfwSetWindowTitle(w, ctitle)
}

func GetKey(w *C.GLFWwindow, key int) Press {
	return Press(C.glfwGetKey(w, C.int(key)))
}

// Time is GLFW's monotonic clock, in seconds.
func Time() float64 { return float64(C.glfwGetTime()) }

// RefreshRate reports the primary monitor's refresh rate in Hz (0 if unknown).
func RefreshRate() int {
	m := C.glfwGetPrimaryMonitor()
	if m == nil {
		return 0
	}
	vm := C.glfwGetVideoMode(m)
	if vm == nil {
		return 0
	}
	return int(vm.refreshRate)
}

func DestroyWindow(w *C.GLFWwindow) { C.glfwDestroyWindow(w) }

func ShowWindow(w *C.GLFWwindow) { C.glfwShowWindow(w) }

// FocusWindow raises the window and, on macOS, activates the process so it
// stops hiding behind whatever was frontmost.
func FocusWindow(w *C.GLFWwindow) {
	C.glfwShowWindow(w)
	C.glfwFocusWindow(w)
	C.goose_activate()
}

func SetWindowPos(w *C.GLFWwindow, x, y int) {
	C.glfwSetWindowPos(w, C.int(x), C.int(y))
}

// MonitorWorkArea reports the primary display's usable size in screen coords.
func MonitorWorkArea() (int, int) {
	m := C.glfwGetPrimaryMonitor()
	if m == nil {
		return 0, 0
	}
	var x, y, w, h C.int
	C.glfwGetMonitorWorkarea(m, &x, &y, &w, &h)
	return int(w), int(h)
}

func SetInputModeStickyKeys() {}

func DefaultWindowHints() { C.glfwDefaultWindowHints() }

// SetFullscreen toggles between borderless fullscreen on the primary monitor
// and a window of the given size.
func SetFullscreen(w *C.GLFWwindow, on bool, ww, wh int) {
	cv := C.int(0)
	if on {
		cv = 1
	}
	C.goose_fullscreen(w, cv, C.int(ww), C.int(wh))
}

func SetWindowSizeLimits(w *C.GLFWwindow, minw, minh, maxw, maxh int) {
	C.glfwSetWindowSizeLimits(w, C.int(minw), C.int(minh), C.int(maxw), C.int(maxh))
}
