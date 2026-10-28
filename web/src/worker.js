// One worker per pane: each language renders on its own thread, so comparing
// two of them costs no frame rate, and the time it reports is the port's
// render alone, without the page's drawing.

import { fromWasm, fromModule } from './host/ports.js';

// Every JavaScript-hosted port, loaded only when a pane asks for it: some
// bring an interpreter of several megabytes.
const modules = import.meta.glob('../../ports/*/port.js');
const moduleOf = (lang) => modules[`../../ports/${lang}/port.js`];

let port = null;
let w = 0;
let h = 0;

const log = (line) => self.postMessage({ type: 'log', line });

self.onmessage = async ({ data: msg }) => {
  try {
    await handle(msg);
  } catch (err) {
    // reply anyway: the page waits for an answer to every request
    self.postMessage({ type: 'error', message: String(err?.stack || err) });
  }
};

async function handle(msg) {
  switch (msg.type) {
    case 'load': {
      let bytes = 0;
      if (moduleOf(msg.lang)) {
        port = await fromModule(await moduleOf(msg.lang)());
      } else {
        const buf = await (await fetch(msg.url)).arrayBuffer();
        bytes = buf.byteLength;
        port = await fromWasm(buf, log);
      }
      self.postMessage({ type: 'loaded', bytes });
      break;
    }
    case 'init':
      w = msg.w;
      h = msg.h;
      port.init(w, h);
      self.postMessage({ type: 'ready' });
      break;
    case 'start':
      port.start(msg.scene);
      port.step(msg.step || 0);
      self.postMessage({ type: 'ready' });
      break;
    case 'render': {
      // Replaying frames the page skipped (after a seek) keeps the stateful
      // scenes on the same history as every other language.
      let ms = 0;
      for (let n = msg.from; n <= msg.n; n++) {
        const t = performance.now();
        await port.render(n);
        ms = performance.now() - t;
      }
      const pixels = port.pixels().slice().buffer;
      self.postMessage({ type: 'frame', n: msg.n, ms, pixels }, [pixels]);
      break;
    }
  }
}
