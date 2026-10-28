import { EFFECTS, LANGS } from './content.js';
import { EXCERPTS } from './excerpts.js';

// --- state ---------------------------------------------------------------

const state = {
  scene: 2, // PLASMA: the effect everybody knows, and a light one
  langs: ['go', null], // pane 0 always shows a language; pane 1 is the comparison
  playing: true,
  n: 0, // last frame drawn
  w: 640,
  h: 360,
  diff: false,
};

const available = new Set(['js']);
const $ = (id) => document.getElementById(id);
const wasmUrl = (lang) => `${import.meta.env.BASE_URL}wasm/${lang}.wasm`;
const langOf = (id) => LANGS.find((l) => l.id === id);

// --- panes: one worker and one canvas per language on screen -----------

class Pane {
  constructor(el) {
    this.el = el;
    this.canvas = el.querySelector('canvas');
    this.ctx = this.canvas.getContext('2d');
    this.lang = null;
    this.worker = null;
    this.times = [];
    this.pixels = null;
    this.drawn = 0; // last frame this pane's worker has rendered
  }

  // call sends one message and resolves with the worker's next reply; the
  // page never has two requests in flight to the same worker.
  call(msg, transfer) {
    return new Promise((resolve) => {
      this.resolve = resolve;
      this.worker.postMessage(msg, transfer || []);
    });
  }

  async load(lang) {
    this.worker?.terminate();
    this.lang = lang;
    this.times = [];
    this.pixels = null;
    this.worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
    this.worker.onmessage = ({ data }) => {
      if (data.type === 'log') return console.log(`[${this.lang}] ${data.line}`);
      this.resolve?.(data);
    };
    const { bytes } = await this.call({ type: 'load', lang, url: wasmUrl(lang) });
    this.bytes = bytes;
    await this.init();
  }

  async init() {
    this.canvas.width = state.w;
    this.canvas.height = state.h;
    this.image = this.ctx.createImageData(state.w, state.h);
    await this.call({ type: 'init', w: state.w, h: state.h });
  }

  async start(scene) {
    this.drawn = 0;
    this.times = [];
    await this.call({ type: 'start', scene });
  }

  // render brings the pane to frame n, replaying any frames it has not seen
  async render(n) {
    const r = await this.call({ type: 'render', from: this.drawn + 1, n });
    this.drawn = n;
    this.pixels = new Uint32Array(r.pixels);
    this.times.push(r.ms);
    if (this.times.length > 30) this.times.shift();
  }

  ms() {
    const t = [...this.times].sort((a, b) => a - b);
    return t.length ? t[t.length >> 1] : 0;
  }

  show(pixels) {
    this.image.data.set(new Uint8ClampedArray(pixels.buffer));
    this.ctx.putImageData(this.image, 0, 0);
  }
}

const panes = [...document.querySelectorAll('.pane')].map((el) => new Pane(el));
const active = () => panes.filter((p, i) => state.langs[i]);

// --- the frame loop ----------------------------------------------------

let busy = false;
let lastTick = 0;
let fpsT = performance.now();
let fpsN = 0;

async function advance() {
  busy = true;
  const max = EFFECTS[state.scene].seconds * 60;
  if (state.n >= max) await restartScene();
  const n = state.n + 1;
  await Promise.all(active().map((p) => p.render(n)));
  state.n = n;
  present();
  busy = false;
}

function loop(now) {
  requestAnimationFrame(loop);
  // 60 Hz at most, whatever the display, because a frame number is a time
  if (!state.playing || busy || now - lastTick < 16) return;
  lastTick = now;
  advance();
  fpsN++;
  if (now - fpsT > 1000) {
    $('fps').textContent = `${Math.round((fpsN * 1000) / (now - fpsT))} fps`;
    fpsT = now;
    fpsN = 0;
  }
}

function present() {
  const [a, b] = panes;
  a.show(a.pixels);
  if (state.langs[1] && b.pixels) {
    const d = compare(a.pixels, b.pixels);
    b.show(state.diff ? d.image : b.pixels);
    showVerdict(d);
  }
  $('frame').textContent = `frame ${state.n}`;
  panes.forEach((p, i) => {
    if (!state.langs[i]) return;
    p.el.querySelector('.ms').textContent = `${p.ms().toFixed(2)} ms`;
  });
}

// compare counts differing pixels and builds the diff view: identical
// pixels dimmed to grey, differing ones in full magenta.
let diffBuf = null;
function compare(a, b) {
  if (!diffBuf || diffBuf.length !== a.length) diffBuf = new Uint32Array(a.length);
  let n = 0;
  for (let i = 0; i < a.length; i++) {
    const p = a[i];
    if (p === b[i]) {
      const g = (((p & 255) + ((p >>> 8) & 255) + ((p >>> 16) & 255)) / 12) | 0;
      diffBuf[i] = 0xff000000 | (g << 16) | (g << 8) | g;
    } else {
      diffBuf[i] = 0xffff40ff;
      n++;
    }
  }
  return { n, image: diffBuf };
}

function showVerdict({ n }) {
  const [a, b] = state.langs.map(langOf);
  const total = state.w * state.h;
  const p = $('verdictText');
  if (n === 0) {
    p.className = 'same';
    p.textContent = `${a.name} and ${b.name}: identical, all ${total.toLocaleString('en')} pixels.`;
  } else {
    p.className = 'differ';
    const pct = ((100 * n) / total).toFixed(n * 1000 < total ? 3 : 1);
    p.textContent = `${n.toLocaleString('en')} pixels differ (${pct}%).`;
  }
}

// --- actions -------------------------------------------------------------

async function restartScene() {
  state.n = 0;
  await Promise.all(active().map((p) => p.start(state.scene)));
}

async function selectScene(i) {
  state.scene = (i + EFFECTS.length) % EFFECTS.length;
  renderChrome();
  busy = true;
  await restartScene();
  busy = false;
  if (!state.playing) await advance();
}

async function selectLang(pane, lang) {
  if (pane === 0 && !lang) return;
  if (lang && !available.has(lang)) return;
  state.langs[pane] = lang;
  const p = panes[pane];
  p.el.hidden = !lang;
  renderChrome();
  if (!lang) {
    p.worker?.terminate();
    p.worker = null;
    return;
  }
  busy = true;
  await p.load(lang);
  await p.start(state.scene);
  // catch up to the frame on screen, so the switch keeps the same instant
  if (state.n > 0) await p.render(state.n);
  present();
  busy = false;
}

async function setResolution(value) {
  [state.w, state.h] = value.split('x').map(Number);
  busy = true;
  for (const p of active()) await p.init();
  await restartScene();
  busy = false;
  if (!state.playing) await advance();
}

function togglePlay() {
  state.playing = !state.playing;
  $('play').textContent = state.playing ? '❚❚' : '▶';
  if (!state.playing) $('fps').textContent = 'paused';
}

async function step() {
  if (state.playing) togglePlay();
  if (!busy) await advance();
}

function toggleDiff(on = !state.diff) {
  state.diff = on;
  $('diff').checked = on;
  if (!state.playing && state.n) present();
}

// --- chrome: everything around the canvases ------------------------------

function renderChrome() {
  const eff = EFFECTS[state.scene];

  $('effects').innerHTML = EFFECTS.map(
    (e, i) => `<button data-scene="${i}" aria-current="${i === state.scene}">
      <span class="num">${String(i + 1).padStart(2, '0')}</span>
      <span class="name">${e.name}</span>
      <span class="sub">${e.trick}</span>
    </button>`,
  ).join('');

  const pill = (pane, l) => {
    const on = state.langs[pane] === (l?.id ?? null);
    if (!l) return `<button role="radio" data-pane="${pane}" data-lang="" aria-checked="${on}">none</button>`;
    const off = !available.has(l.id) || (pane === 1 && state.langs[0] === l.id);
    return `<button role="radio" data-pane="${pane}" data-lang="${l.id}" aria-checked="${on}"
      style="--c:${l.color}" ${off ? 'disabled' : ''}
      title="${available.has(l.id) ? l.how : 'Not built yet'}">${l.name}</button>`;
  };
  $('pickA').innerHTML = LANGS.map((l) => pill(0, l)).join('');
  $('pickB').innerHTML = [pill(1, null), ...LANGS.map((l) => pill(1, l))].join('');

  $('verdict').hidden = !state.langs[1];
  if (!state.langs[1]) toggleDiff(false);

  panes.forEach((p, i) => {
    const l = langOf(state.langs[i]);
    if (!l) return;
    const who = p.el.querySelector('.who');
    who.textContent = l.name;
    who.style.color = l.color;
  });

  $('effName').textContent = eff.name;
  $('effTrick').textContent = eff.trick;
  $('effText').textContent = eff.text;

  renderCode();
}

let highlighter = null;

function renderCode() {
  const eff = EFFECTS[state.scene];
  const shown = state.langs.filter(Boolean);
  $('code').innerHTML = shown
    .map((id) => {
      const l = langOf(id);
      const ex = EXCERPTS[id]?.[eff.name];
      const size = panes[state.langs.indexOf(id)].bytes;
      const kb = size ? ` · ${(size / 1024).toFixed(0)} KB module` : '';
      const body = !ex
        ? `<p class="missing">No excerpt for ${eff.name} in ${l.name} yet.</p>`
        : highlighter
          ? highlighter.codeToHtml(ex.code, { lang: l.hl, theme: 'github-dark-dimmed' })
          : `<pre>${escapeHtml(ex.code)}</pre>`;
      return `<article class="excerpt" style="--c:${l.color}">
        <header><b>${l.name}</b><span class="how">${l.how}${kb}</span>
          <span>${ex ? `${ex.file}:${ex.line}` : ''}</span></header>
        <div class="body">${body}</div>
      </article>`;
    })
    .join('');
}

const escapeHtml = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);

// --- wiring ---------------------------------------------------------------

document.addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  if (b.dataset.scene) selectScene(Number(b.dataset.scene));
  else if (b.dataset.pane) selectLang(Number(b.dataset.pane), b.dataset.lang || null);
});
$('play').onclick = togglePlay;
$('step').onclick = step;
$('restart').onclick = () => selectScene(state.scene);
$('diff').onchange = (e) => toggleDiff(e.target.checked);
$('res').onchange = (e) => setResolution(e.target.value);

document.addEventListener('keydown', (e) => {
  if (e.target.closest('select, input') || e.metaKey || e.ctrlKey || e.altKey) return;
  const k = e.key;
  if (k === ' ') {
    e.preventDefault();
    togglePlay();
  } else if (k === 'ArrowDown' || k === 'ArrowRight') {
    e.preventDefault();
    selectScene(state.scene + 1);
  } else if (k === 'ArrowUp' || k === 'ArrowLeft') {
    e.preventDefault();
    selectScene(state.scene - 1);
  } else if (k === '.') step();
  else if (k === 'r') selectScene(state.scene);
  else if (k === 'd' && state.langs[1]) toggleDiff();
  else if (k >= '1' && k <= String(LANGS.length)) {
    // a number picks the comparison language; shift+number the main one
    const id = LANGS[Number(k) - 1].id;
    if (e.shiftKey) selectLang(0, id);
    else selectLang(1, state.langs[1] === id ? null : id);
  }
});

// --- start ----------------------------------------------------------------

async function main() {
  // a language is offered only once its module is actually there
  await Promise.all(
    LANGS.filter((l) => l.id !== 'js').map(async (l) => {
      const r = await fetch(wasmUrl(l.id), { method: 'HEAD' }).catch(() => null);
      if (r?.ok && !r.headers.get('content-type')?.includes('text/html')) available.add(l.id);
    }),
  );
  if (!Object.keys(EXCERPTS.js).length) available.delete('js');

  renderChrome();
  await panes[0].load(state.langs[0]);
  await panes[0].start(state.scene);
  renderChrome(); // now with the module size
  requestAnimationFrame(loop);

  const { createHighlighter } = await import('shiki');
  highlighter = await createHighlighter({
    themes: ['github-dark-dimmed'],
    langs: LANGS.map((l) => l.hl),
  });
  renderCode();
}

main();
