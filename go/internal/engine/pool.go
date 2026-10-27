package engine

import (
	"rosette/internal/canvas"
	"rosette/internal/fx"
)

// bandPool keeps N goroutines parked between frames. Rendering a frame means
// waking them with the band they own, then waiting for the last one. No
// goroutine is created per frame and no closure is allocated: the work is
// published through the pool's fields and the channel send is the barrier.
type bandPool struct {
	n      int
	goCh   []chan struct{}
	doneCh []chan struct{}
	bands  []band
	eff    fx.Effect
	fb     *canvas.FB
}

type band struct{ y0, y1 int }

func newBandPool(n int) *bandPool {
	if n < 1 {
		n = 1
	}
	p := &bandPool{n: n}
	p.goCh = make([]chan struct{}, n)
	p.doneCh = make([]chan struct{}, n)
	p.bands = make([]band, n)
	for k := 0; k < n; k++ {
		goCh := make(chan struct{})
		doneCh := make(chan struct{})
		p.goCh[k] = goCh
		p.doneCh[k] = doneCh
		go func(k int) {
			for range goCh {
				b := p.bands[k]
				p.eff.Draw(p.fb, b.y0, b.y1)
				doneCh <- struct{}{}
			}
		}(k)
	}
	return p
}

// Run renders eff into fb, splitting the framebuffer into one band per worker.
func (p *bandPool) Run(eff fx.Effect, fb *canvas.FB) {
	if !eff.Parallel() {
		eff.Draw(fb, 0, fb.H)
		return
	}
	h := fb.H
	for k := 0; k < p.n; k++ {
		p.bands[k].y0 = h * k / p.n
		p.bands[k].y1 = h * (k + 1) / p.n
	}
	p.eff = eff
	p.fb = fb
	for k := 0; k < p.n; k++ {
		p.goCh[k] <- struct{}{}
	}
	for k := 0; k < p.n; k++ {
		<-p.doneCh[k]
	}
}

func (p *bandPool) Close() {
	for k := 0; k < p.n; k++ {
		close(p.goCh[k])
	}
}
