// Package fmath holds the numeric shortcuts every effect leans on: a sine
// table and a reciprocal-sqrt approximation. Calling math.Sin a million times
// per frame is the difference between 20 ms and 1 ms, so the hot loops use
// table lookups instead.
package fmath

import (
	"math"
	"unsafe"
)

const (
	TabBits = 13
	TabSize = 1 << TabBits
	TabMask = TabSize - 1
	inv2pi  = TabSize / (2 * math.Pi)
)

var (
	SinTab [TabSize + 1]float32
	CosTab [TabSize + 1]float32
)

func init() {
	for i := 0; i <= TabSize; i++ {
		a := 2 * math.Pi * float64(i) / TabSize
		SinTab[i] = float32(math.Sin(a))
		CosTab[i] = float32(math.Cos(a))
	}
	// guarantee a full period overflows exactly
	SinTab[TabSize] = SinTab[0]
	CosTab[TabSize] = CosTab[0]
}

// Sin returns sin(a) from the table. a is in radians.
func Sin(a float32) float32 {
	i := int(a * inv2pi)
	return SinTab[i&TabMask]
}

// Cos returns cos(a) from the table.
func Cos(a float32) float32 {
	i := int(a * inv2pi)
	return CosTab[i&TabMask]
}

// Sin01 returns sin(2*pi*t) for t in turns.
func Sin01(t float32) float32 {
	i := int(t * TabSize)
	return SinTab[i&TabMask]
}

// Cos01 returns cos(2*pi*t) for t in turns.
func Cos01(t float32) float32 {
	i := int(t * TabSize)
	return CosTab[i&TabMask]
}

// SinT returns sin(turns) with t expressed in turns (float64 convenience).
func SinTurns(t float64) float64 {
	i := int(t * TabSize)
	return float64(SinTab[i&TabMask])
}

// InvSqrt is the classic fast inverse square root (Quake III), good enough for
// shading terms where 1e-3 relative error is invisible.
func InvSqrt(x float32) float32 {
	i := 0x5f3759df - int32(math.Float32bits(x))>>1
	// one Newton step
	y := math.Float32frombits(uint32(i))
	return y * (1.5 - 0.5*x*y*y)
}

// Sqrt is a plain float32 sqrt via math.Sqrt; the hardware instruction is
// already fast, so there is nothing to gain from an approximation here.
func Sqrt(x float32) float32 { return float32(math.Sqrt(float64(x))) }

// Atan2 returns atan2(y, x) as a fraction of a full turn, in [0,1).
func Atan2(y, x float32) float32 {
	a := float32(math.Atan2(float64(y), float64(x)))
	return a/(2*math.Pi) + 0.5
}

// Atan2Tab precomputes the turn fraction of atan2 for a grid, used by the
// tunnel. It is only recomputed when the framebuffer is resized.
func Atan2Tab(w, h int) []float32 {
	cx, cy := float32(w)/2, float32(h)/2
	tab := make([]float32, w*h)
	for y := 0; y < h; y++ {
		dy := float32(y) - cy
		for x := 0; x < w; x++ {
			tab[y*w+x] = Atan2(dy, float32(x)-cx)
		}
	}
	return tab
}

// DistInvTab precomputes scale/(r+softness) for a grid, used by the tunnel.
// The softness term tames the singularity at the centre, which would
// otherwise turn into aliasing noise.
func DistInvTab(w, h int, scale, softness float32) []float32 {
	cx, cy := float32(w)/2, float32(h)/2
	tab := make([]float32, w*h)
	for y := 0; y < h; y++ {
		dy := float32(y) - cy
		for x := 0; x < w; x++ {
			dx := float32(x) - cx
			r := Sqrt(dx*dx+dy*dy) + softness
			tab[y*w+x] = scale / r
		}
	}
	return tab
}

// AsBytes reinterprets a []uint32 pixel buffer as bytes without copying.
func AsBytes(p []uint32) []byte {
	if len(p) == 0 {
		return nil
	}
	return unsafe.Slice((*byte)(unsafe.Pointer(&p[0])), len(p)*4)
}
