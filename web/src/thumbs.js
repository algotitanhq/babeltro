// The home page's live thumbnails: one worker, one instance of a fast port
// per scene, each drawing straight into its card's OffscreenCanvas. The page
// itself never touches a pixel.

import { fromWasm } from './host/ports.js';

const cards = [];
let running = false;
let timer = 0;

self.onmessage = async ({ data: msg }) => {
  if (msg.type === 'init') {
    const module = await WebAssembly.compileStreaming(fetch(msg.url));
    for (let scene = 0; scene < msg.canvases.length; scene++) {
      const canvas = msg.canvases[scene];
      const port = await fromWasm(module, () => {});
      port.init(canvas.width, canvas.height);
      port.start(scene);
      const ctx = canvas.getContext('2d');
      const image = ctx.createImageData(canvas.width, canvas.height);
      cards.push({ port, ctx, image, n: 0, max: msg.seconds[scene] * 60, scene });
    }
    running = true;
    tick();
  } else if (msg.type === 'run') {
    if (msg.on && !running) {
      running = true;
      tick();
    }
    running = msg.on;
  }
};

// 30 frames a second is plenty for a thumbnail, and halves the cost
function tick() {
  clearTimeout(timer);
  if (!running) return;
  const t0 = performance.now();
  for (const c of cards) {
    if (++c.n > c.max) {
      c.port.start(c.scene);
      c.n = 1;
    }
    // two frames per tick: the scene runs at its real speed at 30 fps
    c.port.render(c.n);
    if (++c.n <= c.max) c.port.render(c.n);
    c.image.data.set(new Uint8ClampedArray(c.port.pixels().buffer, c.port.pixels().byteOffset, c.image.data.length));
    c.ctx.putImageData(c.image, 0, 0);
  }
  timer = setTimeout(tick, Math.max(0, 33 - (performance.now() - t0)));
}
