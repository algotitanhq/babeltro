import { EFFECTS, LANGS, HOME } from './content.js';
import { EXCERPTS, NOTES } from './excerpts.js';

const $ = (id) => document.getElementById(id);
const wasmUrl = (lang) => `${import.meta.env.BASE_URL}wasm/${lang}.wasm`;
const langOf = (id) => LANGS.find((l) => l.id === id);
const slug = (name) => name.toLowerCase();

// --- state ---------------------------------------------------------------

const state = {
  view: 'home',
  scene: 2,
  lang: 'go', // the main pane
  other: null, // a second language on the same frames, or null
  rung: 0, // ladder rung, 1..steps.length; ignored for scenes without one
  vsBest: false, // second pane: the same language at the last rung
  playing: true,
  n: 0, // last frame drawn
  w: 640,
  h: 360,
  diff: false,
};

const available = new Set();

const steps = () => EFFECTS[state.scene].steps;
// the port's step number for a rung: the last rung is the default, 0
const stepOf = (rung) => (!steps() || rung >= steps().length ? 0 : rung);
const rungOf = (step) => (step === 0 ? (steps()?.length ?? 0) : step);

// spec says what pane i should show: a language and a ladder step, or null
function spec(i) {
  if (i === 0) return { lang: state.lang, step: stepOf(state.rung) };
  if (state.vsBest && steps()) return { lang: state.lang, step: 0 };
  if (state.other) return { lang: state.other, step: stepOf(state.rung) };
  return null;
}

// --- panes: one worker and one canvas each --------------------------------

class Pane {
  constructor(el) {
    this.el = el;
    this.canvas = el.querySelector('canvas');
    this.ctx = this.canvas.getContext('2d');
    this.lang = null;
    this.step = 0;
    this.scene = -1;
    this.worker = null;
    this.times = [];
    this.pixels = null;
    this.drawn = 0; // last frame this pane's worker has rendered
  }

  // call sends one message and resolves with the worker's reply; the queue
  // below guarantees there is never more than one in flight
  call(msg) {
    return new Promise((resolve, reject) => {
      this.resolve = resolve;
      this.reject = reject;
      this.worker.postMessage(msg);
    });
  }

  async load(lang) {
    this.drop();
    this.lang = lang;
    this.worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
    this.worker.onerror = (e) => this.reject?.(new Error(`${lang} worker: ${e.message}`));
    this.worker.onmessage = ({ data }) => {
      if (data.type === 'log') return console.log(`[${this.lang}] ${data.line}`);
      if (data.type === 'error') return this.reject?.(new Error(`${this.lang}: ${data.message}`));
      this.resolve?.(data);
    };
    const { bytes } = await this.call({ type: 'load', lang, url: wasmUrl(lang) });
    this.bytes = bytes;
    await this.init();
  }

  drop() {
    this.worker?.terminate();
    this.worker = null;
    this.lang = null;
    this.scene = -1;
    this.pixels = null;
  }

  async init() {
    this.canvas.width = state.w;
    this.canvas.height = state.h;
    this.image = this.ctx.createImageData(state.w, state.h);
    await this.call({ type: 'init', w: state.w, h: state.h });
    this.scene = -1;
  }

  async start(scene, step) {
    this.scene = scene;
    this.step = step;
    this.drawn = 0;
    this.times = [];
    await this.call({ type: 'start', scene, step });
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
const active = () => panes.filter((p) => p.worker);

// Every operation that talks to the workers goes through one queue: a frame
// in flight and a language being swapped in must never interleave, or the
// replies would answer the wrong requests.
let queue = Promise.resolve();
let pending = 0;
function exclusive(fn) {
  pending++;
  const run = queue.then(fn).finally(() => pending--);
  queue = run.catch((err) => console.error(err));
  return run;
}

// sync makes every pane match its spec, keeping the frame on screen: a pane
// that changes language or step replays up to the current frame, so the
// switch shows the same instant.
async function sync() {
  for (const [i, p] of panes.entries()) {
    const s = spec(i);
    p.el.hidden = !s;
    if (!s) {
      p.drop();
      continue;
    }
    if (p.lang !== s.lang) await p.load(s.lang);
    if (p.scene !== state.scene || p.step !== s.step) {
      await p.start(state.scene, s.step);
      if (state.n > 0) await p.render(state.n);
    }
  }
  renderChrome();
  if (state.n > 0) present();
}

// --- the frame loop ----------------------------------------------------

let lastTick = 0;
let fpsT = performance.now();
let fpsN = 0;

async function advance() {
  if (state.n >= EFFECTS[state.scene].seconds * 60) {
    state.n = 0;
    for (const p of active()) await p.start(state.scene, p.step);
  }
  const n = state.n + 1;
  await Promise.all(active().map((p) => p.render(n)));
  state.n = n;
  present();
}

function loop(now) {
  requestAnimationFrame(loop);
  // 60 Hz at most, whatever the display, because a frame number is a time
  if (state.view !== 'lab' || !state.playing || pending || now - lastTick < 16) return;
  lastTick = now;
  exclusive(advance);
  fpsN++;
  if (now - fpsT > 1000) {
    $('fps').textContent = `${Math.round((fpsN * 1000) / (now - fpsT))} fps on screen`;
    fpsT = now;
    fpsN = 0;
  }
}

function present() {
  const [a, b] = panes;
  if (!a.pixels) return;
  a.show(a.pixels);
  if (b.worker && b.pixels) {
    const d = compare(a.pixels, b.pixels);
    b.show(state.diff ? d.image : b.pixels);
    showVerdict(d);
  }
  $('frame').textContent = `frame ${state.n}`;
  for (const p of active()) {
    const ms = p.ms();
    p.el.querySelector('.ms').textContent = `${ms.toFixed(2)} ms per frame`;
    const bar = p.el.querySelector('.bar i');
    bar.style.width = `${Math.min(100, (ms / 16.67) * 100)}%`;
    bar.classList.toggle('over', ms > 16.67);
  }
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
  const total = state.w * state.h;
  const p = $('verdictText');
  const [a, b] = panes.map(caption);
  if (n === 0) {
    p.className = 'same';
    p.textContent = `Identical: all ${total.toLocaleString('en')} pixels of ${b} match ${a}.`;
  } else {
    p.className = 'differ';
    const pct = ((100 * n) / total).toFixed(n * 1000 < total ? 3 : 1);
    p.textContent = `${n.toLocaleString('en')} of ${total.toLocaleString('en')} pixels differ (${pct}%) between ${a} and ${b}.`;
  }
}

// caption names what a pane shows: the language, and the rung on a ladder
function caption(p) {
  const l = langOf(p.lang);
  if (!l) return '';
  return steps() ? `${l.name}, step ${rungOf(p.step)}` : l.name;
}

// --- actions -------------------------------------------------------------

const update = (fn) =>
  exclusive(async () => {
    fn();
    await sync();
    if (!state.playing && state.n === 0) await advance();
  });

function selectScene(i) {
  return update(() => {
    state.scene = (i + EFFECTS.length) % EFFECTS.length;
    state.rung = steps()?.length ?? 0;
    state.n = 0;
    for (const p of panes) p.scene = -1;
  });
}

function selectLang(pane, lang) {
  if (lang && !available.has(lang)) return;
  return update(() => {
    if (pane === 0) {
      if (!lang) return;
      if (state.other === lang) state.other = state.lang;
      state.lang = lang;
    } else {
      state.other = lang === state.lang ? null : lang;
      if (lang) state.vsBest = false;
    }
  });
}

function selectRung(r) {
  return update(() => {
    state.rung = r;
    if (r === steps().length) state.vsBest = false;
  });
}

function setVsBest(on) {
  return update(() => {
    state.vsBest = on;
    if (on) state.other = null;
  });
}

const setResolution = (value) =>
  exclusive(async () => {
    [state.w, state.h] = value.split('x').map(Number);
    for (const p of active()) await p.init();
    state.n = 0;
    await sync();
    if (!state.playing) await advance();
  });

function togglePlay() {
  state.playing = !state.playing;
  $('play').textContent = state.playing ? '❚❚' : '▶';
  if (!state.playing) $('fps').textContent = 'paused';
}

function step() {
  if (state.playing) togglePlay();
  if (!pending) exclusive(advance);
}

function toggleDiff(on = !state.diff) {
  state.diff = on;
  $('diff').checked = on;
  $('legend').hidden = !on;
  if (state.n) present();
}

// --- chrome: everything around the canvases ------------------------------

function renderChrome() {
  const eff = EFFECTS[state.scene];

  $('effects').innerHTML = EFFECTS.map(
    (e, i) => `<a href="#/${slug(e.name)}" aria-current="${i === state.scene}">
      <span class="num">${String(i + 1).padStart(2, '0')}</span>
      <span class="name">${e.name}</span>
      <span class="sub">${e.trick}</span>
    </a>`,
  ).join('');

  const pill = (pane, l, on) => {
    if (!l) return `<button role="radio" data-pane="${pane}" data-lang="" aria-checked="${on}">none</button>`;
    const off = !available.has(l.id) || (pane === 1 && state.lang === l.id);
    return `<button role="radio" data-pane="${pane}" data-lang="${l.id}" aria-checked="${on}"
      style="--c:${l.color}" ${off ? 'disabled' : ''}
      title="${available.has(l.id) ? l.how : 'Not built yet'}">${l.name}</button>`;
  };
  $('pickA').innerHTML = LANGS.map((l) => pill(0, l, state.lang === l.id)).join('');
  $('pickB').innerHTML = [
    pill(1, null, !state.other),
    ...LANGS.map((l) => pill(1, l, state.other === l.id)),
  ].join('');
  $('compareHint').hidden = !!state.other;

  const st = eff.steps;
  $('ladder').hidden = !st;
  if (st) {
    $('steps').innerHTML = st
      .map(
        (s, i) => `<li><button data-rung="${i + 1}" aria-pressed="${state.rung === i + 1}">
          <b>${i + 1}</b><span><span class="sname">${s.name}</span><span class="stext">${s.text}</span></span>
        </button></li>`,
      )
      .join('');
    $('vsBest').checked = state.vsBest;
    $('vsBest').disabled = state.rung === st.length;
  }

  const comparing = !!spec(1);
  $('verdict').hidden = !comparing;
  if (!comparing && state.diff) toggleDiff(false);

  panes.forEach((p, i) => {
    const s = spec(i);
    if (!s) return;
    const l = langOf(s.lang);
    const who = p.el.querySelector('.who');
    who.textContent = st ? `${l.name} · step ${rungOf(s.step)}` : l.name;
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
  const shown = [spec(0), spec(1)].filter(Boolean);
  $('code').innerHTML = shown
    .map((s) => {
      const l = langOf(s.lang);
      const rung = rungOf(s.step);
      const key = s.step ? `${eff.name}/${s.step}` : eff.name;
      const ex = EXCERPTS[s.lang]?.[key];
      const pane = panes.find((p) => p.lang === s.lang);
      const kb = pane?.bytes ? ` · ${(pane.bytes / 1024).toFixed(0)} KB module` : '';
      const note =
        NOTES[s.lang]?.[key] ??
        (s.lang === 'go' && !s.step ? 'The reference: every other language must match these pixels.' : '');
      const label = eff.steps ? ` · step ${rung}: ${eff.steps[rung - 1].name}` : '';
      const body = !ex
        ? `<p class="missing">${l.name} has no excerpt for this ${eff.steps ? 'step' : 'effect'} yet.</p>`
        : highlighter
          ? highlighter.codeToHtml(ex.code, { lang: l.hl, theme: 'github-dark-dimmed' })
          : `<pre>${escapeHtml(ex.code)}</pre>`;
      return `<article class="excerpt" style="--c:${l.color}">
        <header><b>${l.name}${label}</b><span class="how">${l.how}${kb}</span>
          <span class="where">${ex ? `${ex.file}:${ex.line}` : ''}</span></header>
        ${note ? `<p class="note">${inline(note)}</p>` : ''}
        <div class="body">${body}</div>
      </article>`;
    })
    .join('');
}

// inline renders the little Markdown the notes use: `code` and **bold**
const inline = (s) =>
  escapeHtml(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');

const escapeHtml = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);

// --- home ------------------------------------------------------------------

// Where each card sits around the question, in % of the page, and its tilt.
// Hand-placed: a scatter, not a grid.
const SCATTER = [
  [13, 20, -5], [38, 13, 3], [63, 15, -2], [87, 22, 5],
  [10, 55, 4], [90, 56, -4],
  [17, 86, 3], [50, 88, -3], [83, 85, 2],
];

let thumbs = null;

function buildHome() {
  $('intro').textContent = HOME.intro;
  $('cards').innerHTML = EFFECTS.map((e, i) => {
    const [x, y, r] = SCATTER[i];
    return `<a class="card" href="#/${slug(e.name)}" style="--x:${x}%;--y:${y}%;--r:${r}deg">
      <canvas width="256" height="144"></canvas>
      <span class="label"><b>${String(i + 1).padStart(2, '0')}</b> ${e.name}</span>
      <span class="trick">${e.trick}</span>
    </a>`;
  }).join('');

  // the question cycles through the languages, in their colours
  const langs = LANGS.filter((l) => available.has(l.id));
  let k = 0;
  const q = $('qlang');
  q.textContent = langs[0].name;
  q.style.color = langs[0].color;
  setInterval(() => {
    if (state.view !== 'home') return;
    k = (k + 1) % langs.length;
    q.textContent = langs[k].name;
    q.style.color = langs[k].color;
  }, 1600);

  // the thumbnails come from the reference: at 256×144 even Go's slowest
  // scene costs about a millisecond, and the finale card then spells GO
  const port = available.has('go') ? 'go' : null;
  const canvases = [...$('cards').querySelectorAll('canvas')];
  if (!port || !canvases[0].transferControlToOffscreen) return;
  const offscreen = canvases.map((c) => c.transferControlToOffscreen());
  thumbs = new Worker(new URL('./thumbs.js', import.meta.url), { type: 'module' });
  thumbs.postMessage(
    { type: 'init', url: wasmUrl(port), canvases: offscreen, seconds: EFFECTS.map((e) => e.seconds) },
    offscreen,
  );
}

// --- routing: #/ is home, #/plasma is the lab on that effect --------------

async function route() {
  const name = location.hash.replace(/^#\/?/, '').toUpperCase();
  const i = EFFECTS.findIndex((e) => e.name === name);
  state.view = i < 0 ? 'home' : 'lab';
  document.body.className = `is-${state.view}`;
  thumbs?.postMessage({ type: 'run', on: state.view === 'home' });
  if (state.view === 'lab') {
    document.title = `${EFFECTS[i].name.toLowerCase()} · babeltro`;
    if (i !== state.scene || !panes[0].worker) await selectScene(i);
  } else {
    document.title = 'babeltro';
  }
}

// --- wiring ---------------------------------------------------------------

document.addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  if (b.dataset.pane) selectLang(Number(b.dataset.pane), b.dataset.lang || null);
  else if (b.dataset.rung) selectRung(Number(b.dataset.rung));
});
$('play').onclick = togglePlay;
$('step').onclick = step;
$('restart').onclick = () => selectScene(state.scene);
$('diff').onchange = (e) => toggleDiff(e.target.checked);
$('vsBest').onchange = (e) => setVsBest(e.target.checked);
$('res').onchange = (e) => setResolution(e.target.value);
window.addEventListener('hashchange', route);

document.addEventListener('keydown', (e) => {
  if (state.view !== 'lab') return;
  if (e.target.closest('select, input') || e.metaKey || e.ctrlKey || e.altKey) return;
  const k = e.key;
  const go = (i) => (location.hash = `#/${slug(EFFECTS[(i + EFFECTS.length) % EFFECTS.length].name)}`);
  if (k === ' ') {
    e.preventDefault();
    togglePlay();
  } else if (k === 'ArrowDown' || k === 'ArrowRight') {
    e.preventDefault();
    go(state.scene + 1);
  } else if (k === 'ArrowUp' || k === 'ArrowLeft') {
    e.preventDefault();
    go(state.scene - 1);
  } else if (k === 'Escape') location.hash = '#/';
  else if (k === '.') step();
  else if (k === 'r') selectScene(state.scene);
  else if (k === 'd' && spec(1)) toggleDiff();
  else if (/^Digit[1-9]$/.test(e.code)) {
    // a number picks the comparison language; shift+number the main one
    const id = LANGS[Number(e.code.slice(5)) - 1]?.id;
    if (!id) return;
    if (e.shiftKey) selectLang(0, id);
    else selectLang(1, state.other === id ? null : id);
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
  if (Object.keys(EXCERPTS.js).length) available.add('js');

  buildHome();
  await route();
  requestAnimationFrame(loop);

  // only the five grammars and one theme: the full shiki bundle is megabytes
  const [{ createHighlighterCore }, { createJavaScriptRegexEngine }] = await Promise.all([
    import('shiki/core'),
    import('shiki/engine/javascript'),
  ]);
  highlighter = await createHighlighterCore({
    themes: [import('@shikijs/themes/github-dark-dimmed')],
    langs: [
      import('@shikijs/langs/go'),
      import('@shikijs/langs/c'),
      import('@shikijs/langs/rust'),
      import('@shikijs/langs/zig'),
      import('@shikijs/langs/javascript'),
    ],
    engine: createJavaScriptRegexEngine(),
  });
  renderCode();
}

main();
