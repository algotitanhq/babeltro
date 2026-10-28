// The home page's wordmark, drawn the way the demo draws its own: the 5×7
// bitmap font scaled up block by block, a three-stop gradient, a dark edge
// and an additive reflection, with the letters bouncing off the floor. It
// reuses the JavaScript port's text code, so it is the demo's pixels, not a
// web font pretending.

import { Framebuffer } from '../../ports/js/lib/canvas.js';
import { textWidth, textHeight, drawTextGradient, drawTextOutline, drawTextReflect } from '../../ports/js/lib/text.js';

const TOP = 0xfffff6e8; // pale cream
const MID = 0xff7c9cff; // hot rose
const BOT = 0xff582080; // deep violet

export function startLogo(canvas, text, isVisible) {
  const scale = 7;
  const pad = scale; // room for the bounce and the outline
  const w = textWidth(text, scale) + 2 * pad;
  const glyphH = textHeight(scale);
  const reflH = glyphH >> 1; // whole rows: the framebuffer size must be an integer
  const h = glyphH + reflH + 2 * pad;
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  const fb = new Framebuffer(w, h);
  const image = ctx.createImageData(w, h);
  const offs = new Int32Array(text.length);
  const floor = pad + glyphH;

  const frame = (now) => {
    requestAnimationFrame(frame);
    if (!isVisible()) return;
    const t = now / 1000;
    // the same bounce as the finale: up by at most a third of a block
    for (let i = 0; i < offs.length; i++) {
      offs[i] = ((Math.sin(t * 2.4 + i * 0.75) - 1) * scale) / 6;
    }
    fb.pix.fill(0);
    drawTextReflect(fb, pad, floor, text, scale, TOP, BOT, offs, 125, reflH);
    drawTextOutline(fb, pad, pad, text, scale, 0xff200a18, offs);
    drawTextGradient(fb, pad, pad, text, scale, TOP, MID, BOT, offs, true);
    image.data.set(new Uint8ClampedArray(fb.pix.buffer));
    ctx.putImageData(image, 0, 0);
  };
  requestAnimationFrame(frame);
}
