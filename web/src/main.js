import { EFFECTS, LANGS, HOME, TIMING_NOTE } from './content.js';
import { EXCERPTS, NOTES, SOURCES } from './excerpts.js';
import { startLogo } from './logo.js';

const $ = (id) => document.getElementById(id);
const wasmUrl = (lang) => `${import.meta.env.BASE_URL}wasm/${lang}.wasm`;
const langOf = (id) => LANGS.find((l) => l.id === id);
const slug = (name) => name.toLowerCase();

// --- state ---------------------------------------------------------------

const state = {
  view: 'home',
  scene: 2,
  lang: 'c', // the language on screen; C is the reference
  read: null, // a second language whose code is shown next to it, or null
  rung: 0, // ladder rung, 1..steps.length; ignored for scenes without one
  vsBest: false, // second pane: the same language at the last rung
  playing: true,
  n: 0, // last frame drawn
  w: 640,
  h: 360,
  diff: false,
};

const available = new Set();
// a language covers a scene unless its LANGS entry lists the ones it has
const covers = (id, scene = state.scene) => available.has(id) && (!langOf(id)?.scenes || langOf(id).scenes.includes(scene));
// JavaScript-hosted ports: present when ports/<lang>/port.js exists
const modulePorts = Object.keys(import.meta.glob('../../ports/*/port.js')).map((p) => p.split('/')[3]);

const steps = () => EFFECTS[state.scene].steps;
// the port's step number for a rung: the last rung is the default, 0
const stepOf = (rung) => (!steps() || rung >= steps().length ? 0 : rung);
const rungOf = (step) => (step === 0 ? (steps()?.length ?? 0) : step);

// spec says what pane i should show: a language and a ladder step, or null
function spec(i) {
  if (i === 0) return { lang: state.lang, step: stepOf(state.rung) };
  if (state.vsBest && steps()) return { lang: state.lang, step: 0 };
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

// sync makes every pane match its spec. Any change restarts the scene for
// every pane: replaying to the frame on screen would take a minute in Perl.
async function sync() {
  let changed = false;
  for (const [i, p] of panes.entries()) {
    const s = spec(i);
    p.el.hidden = !s;
    if (!s) {
      p.drop();
      continue;
    }
    if (p.lang !== s.lang) {
      await p.load(s.lang);
      changed = true;
    }
    if (p.scene !== state.scene || p.step !== s.step) changed = true;
  }
  if (changed) {
    state.n = 0;
    for (const [i, p] of panes.entries()) if (spec(i)) await p.start(state.scene, spec(i).step);
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

let resized = false;
const update = (fn) =>
  exclusive(async () => {
    fn();
    if (resized) {
      resized = false;
      for (const p of active()) await p.init();
    }
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
  if (lang && !covers(lang)) return;
  return update(() => {
    if (pane === 0) {
      if (!lang) return;
      if (state.read === lang) state.read = null;
      state.lang = lang;
      // a slow interpreter gets a small frame, or each one takes seconds
      const res = langOf(lang).res;
      if (res && state.w * state.h > res[0] * res[1]) {
        [state.w, state.h] = res;
        $('res').value = res.join('x');
        resized = true;
      }
    } else {
      state.read = lang === state.lang ? null : lang;
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

// --- the race: every language on the same scene and step ---------------

// race runs each built language in a worker of its own, one after the other
// so they do not compete for the CPU, on the same 120 frames; it reports the
// median time per frame and whether the last frame matches the reference's.
const RACE_FRAMES = 120;
const RACE_MS = 4000; // a slow interpreter stops early: at least 5 frames, at most 4 s
let raceKey = '';

async function race() {
  const wasPlaying = state.playing;
  if (wasPlaying) togglePlay();
  const key = `${state.scene}/${state.rung}/${state.w}x${state.h}`;
  raceKey = key;
  const out = $('raceOut');
  const rows = [];
  const draw = () => {
    const max = Math.max(...rows.map((r) => r.ms || 0), 0.001);
    // native Go, measured once outside the browser, for scale: it is not a
    // row the lab runs, so it is drawn dimmed and only for the default step
    const eff = EFFECTS[state.scene];
    const native =
      eff.native && stepOf(state.rung) === 0 && state.w === 640
        ? `<li class="native" style="--c:#4fc3e8"><span class="rl">Go native</span>
            <span class="rbar"><i style="width:${(eff.native / max) * 100}%"></i></span>
            <span class="rms">${eff.native.toFixed(2)} ms</span>
            <span class="rv">one thread on an M1, outside the browser</span></li>`
        : '';
    out.innerHTML = native + rows
      .map((r) => {
        const l = langOf(r.lang);
        const short = r.frames < RACE_FRAMES ? ` · stopped after ${r.frames} frames` : '';
        const verdict =
          r.ms === undefined
            ? '…'
            : (r.lang === 'c' ? 'reference' : r.diff === 0 ? 'same pixels' : `${r.diff.toLocaleString('en')} px differ`) + short;
        return `<li style="--c:${l.color}">
          <span class="rl">${l.name}</span>
          <span class="rbar"><i style="width:${((r.ms || 0) / max) * 100}%"></i></span>
          <span class="rms">${r.ms === undefined ? '' : `${r.ms.toFixed(2)} ms`}</span>
          <span class="rv ${r.diff ? 'differ' : ''}">${verdict}</span>
        </li>`;
      })
      .join('');
  };
  const langs = ['c', ...LANGS.map((l) => l.id).filter((id) => id !== 'c' && covers(id))];
  for (const lang of langs) rows.push({ lang });
  draw();
  $('timingNote').hidden = false;
  $('race').disabled = true;
  try {
    await runRace(rows, key, draw);
  } finally {
    $('race').disabled = false;
    if (wasPlaying && !state.playing) togglePlay();
  }
}

async function runRace(rows, key, draw) {
  let ref = null;
  for (const r of rows) {
    if (raceKey !== key) break; // the scene changed under us
    // an off-screen pane: same worker protocol, never shown
    const fig = document.createElement('figure');
    fig.append(document.createElement('canvas'));
    const p = new Pane(fig);
    try {
      await p.load(r.lang);
      await p.start(state.scene, stepOf(state.rung));
      const t0 = performance.now();
      let n = 0;
      while (n < RACE_FRAMES && (n < 5 || performance.now() - t0 < RACE_MS)) await p.render(++n);
      r.ms = p.ms();
      r.frames = n;
      if (r.lang === 'c') {
        // keep the reference going so a port that stopped early is compared
        // on the frame it reached
        ref = p;
        draw();
        continue;
      }
      r.diff = ref ? await diffAt(ref, p, n) : undefined;
    } finally {
      if (p !== ref) p.drop();
    }
    draw();
  }
  ref?.drop();
}

// diffAt compares port p, at frame n, with the reference pane replayed to
// the same frame (the reference raced first and ran furthest)
async function diffAt(ref, p, n) {
  if (ref.drawn !== n) {
    await ref.start(state.scene, stepOf(state.rung));
    await ref.render(n);
  }
  return compare(ref.pixels, p.pixels).n;
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
    const off = !covers(l.id) || (pane === 1 && state.lang === l.id);
    const why = !available.has(l.id)
      ? 'Not built yet'
      : !covers(l.id)
        ? `${l.name} only does ${l.scenes.map((i) => EFFECTS[i].name.toLowerCase()).join(', ')} so far`
        : l.how;
    return `<button role="radio" data-pane="${pane}" data-lang="${l.id}" aria-checked="${on}"
      style="--c:${l.color}" ${off ? 'disabled' : ''} title="${why}">${l.name}</button>`;
  };
  $('pickA').innerHTML = LANGS.map((l) => pill(0, l, state.lang === l.id)).join('');
  // say why a language is greyed, in words, not only in a tooltip
  const missing = LANGS.filter((l) => available.has(l.id) && !covers(l.id)).map((l) => l.name);
  $('notHere').textContent = missing.length
    ? `${missing.join(', ')} ${missing.length > 1 ? "don't" : "doesn't"} do this effect yet.`
    : '';
  $('pickB').innerHTML = [
    pill(1, null, !state.read),
    ...LANGS.map((l) => pill(1, l, state.read === l.id)),
  ].join('');

  const st = eff.steps;
  $('ladder').hidden = !st;
  if (st) {
    $('steps').innerHTML = st
      .map(
        (s, i) => `<li><button data-rung="${i + 1}" aria-pressed="${state.rung === i + 1}">
          <b>${i + 1}</b><span><span class="sname">${s.name}${i === st.length - 1 ? ' <em>what the demo runs</em>' : ''}</span><span class="stext">${s.text}</span></span>
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

  const key = `${state.scene}/${state.rung}/${state.w}x${state.h}`;
  if (key !== raceKey) {
    raceKey = '';
    $('raceOut').innerHTML = '';
  }

  $('timingNote').textContent = TIMING_NOTE;

  $('effName').textContent = eff.name;
  $('effTrick').textContent = eff.trick;
  $('effText').textContent = eff.text;

  renderCode();
}

let highlighter = null;

function renderCode() {
  const eff = EFFECTS[state.scene];
  const shown = [spec(0), spec(1) ?? (state.read && { lang: state.read, step: stepOf(state.rung) })].filter(Boolean);
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
        (s.lang === 'c' && !s.step ? 'The reference: every other language must match these pixels.' : '');
      const label = eff.steps ? ` · step ${rung}: ${eff.steps[rung - 1].name}` : '';
      const body = !ex
        ? `<p class="missing">${l.name} has no excerpt for this ${eff.steps ? 'step' : 'effect'} yet.</p>`
        : highlighter
          ? highlighter.codeToHtml(ex.code, { lang: l.hl, theme: 'github-dark-dimmed' })
          : `<pre>${escapeHtml(ex.code)}</pre>`;
      return `<article class="excerpt" style="--c:${l.color}">
        <header><b>${l.name}${label}</b><span class="how">${l.how}${kb}</span>
          ${ex ? `<button class="full" data-src="${s.lang}|${ex.file}|${ex.line}|${ex.end}" title="Open the whole file, with this excerpt highlighted">${ex.file}:${ex.line} · full file</button>` : ''}</header>
        ${note ? `<p class="note">${inline(note)}</p>` : ''}
        <div class="body">${body}</div>
      </article>`;
    })
    .join('');
}

// --- the full-file view ---------------------------------------------------

// openSource shows a port's whole file in a drawer, lines from..to
// highlighted and scrolled into view, with the port's other files listed
// alongside so the excerpt can be read in its context.
function openSource(lang, path, from = 0, to = 0) {
  const l = langOf(lang);
  const files = SOURCES[lang] ?? {};
  const text = files[path] ?? '';
  $('srcLang').textContent = l.name;
  $('srcLang').style.color = l.color;
  $('srcPath').textContent = path;
  $('srcFiles').innerHTML = Object.keys(files)
    .sort()
    .map((p) => `<button data-file="${lang}|${p}" aria-current="${p === path}">${p.split('/').slice(2).join('/') || p}</button>`)
    .join('');
  const mark = {
    line(node, line) {
      if (line >= from && line <= to) this.addClassToHast(node, 'hl');
    },
  };
  $('srcCode').innerHTML = highlighter
    ? highlighter.codeToHtml(text, { lang: l.hl, theme: 'github-dark-dimmed', transformers: [mark] })
    : `<pre>${escapeHtml(text)}</pre>`;
  $('source').hidden = false;
  const first = $('srcCode').querySelector('.hl');
  if (first) first.scrollIntoView({ block: 'center' });
  else $('srcCode').scrollTop = 0;
}

const closeSource = () => ($('source').hidden = true);

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
  [22, 26, -5], [41, 20, 3], [60, 22, -2], [78, 28, 5],
  [20, 54, 4], [80, 55, -4],
  [25, 80, 3], [50, 82, -3], [75, 79, 2],
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
  // fast, like a slot machine: the list is long, and the point is that it
  // keeps going
  setInterval(() => {
    if (state.view !== 'home') return;
    k = (k + 1) % langs.length;
    q.textContent = langs[k].name;
    q.style.color = langs[k].color;
    q.classList.remove('flip');
    void q.offsetWidth; // restart the animation
    q.classList.add('flip');
  }, 400);

  startLogo($('logo'), 'BABELTRO', () => state.view === 'home');

  // the thumbnails come from the reference: at 256×144 even Go's slowest
  // scene costs about a millisecond, and the finale card then spells GO
  const port = available.has('c') ? 'c' : null;
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
  if (e.target.closest('[data-close]')) return closeSource();
  const b = e.target.closest('button');
  if (!b) return;
  if (b.dataset.src) {
    const [lang, path, from, to] = b.dataset.src.split('|');
    openSource(lang, path, Number(from), Number(to));
  } else if (b.dataset.file) {
    const [lang, path] = b.dataset.file.split('|');
    openSource(lang, path);
  } else if (b.dataset.pane) selectLang(Number(b.dataset.pane), b.dataset.lang || null);
  else if (b.dataset.rung) selectRung(Number(b.dataset.rung));
});
$('play').onclick = togglePlay;
$('step').onclick = step;
$('restart').onclick = () => selectScene(state.scene);
$('diff').onchange = (e) => toggleDiff(e.target.checked);
$('race').onclick = race;
$('vsBest').onchange = (e) => setVsBest(e.target.checked);
$('res').onchange = (e) => setResolution(e.target.value);
window.addEventListener('hashchange', route);

document.addEventListener('keydown', (e) => {
  if (!$('source').hidden) {
    if (e.key === 'Escape') closeSource();
    return;
  }
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
    else selectLang(1, state.read === id ? null : id);
  }
});

// --- start ----------------------------------------------------------------

// One import per grammar, spelled out so the bundler can split them.
const GRAMMARS = {
  go: () => import('@shikijs/langs/go'),
  c: () => import('@shikijs/langs/c'),
  cpp: () => import('@shikijs/langs/cpp'),
  rust: () => import('@shikijs/langs/rust'),
  zig: () => import('@shikijs/langs/zig'),
  javascript: () => import('@shikijs/langs/javascript'),
  typescript: () => import('@shikijs/langs/typescript'),
  python: () => import('@shikijs/langs/python'),
  perl: () => import('@shikijs/langs/perl'),
  wasm: () => import('@shikijs/langs/wasm'),
  asm: () => import('@shikijs/langs/asm'),
  sql: () => import('@shikijs/langs/sql'),
};

async function main() {
  // a language is offered only once its module is actually there
  await Promise.all(
    LANGS.filter((l) => !modulePorts.includes(l.id)).map(async (l) => {
      const r = await fetch(wasmUrl(l.id), { method: 'HEAD' }).catch(() => null);
      if (r?.ok && !r.headers.get('content-type')?.includes('text/html')) available.add(l.id);
    }),
  );
  for (const id of modulePorts) available.add(id);

  const count = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty'][available.size] ?? available.size;
  $('tagline').textContent = `Nine demoscene effects · ${count} languages · the same pixels`;
  buildHome();
  await route();
  requestAnimationFrame(loop);

  // only the grammars the ports use and one theme: the full shiki bundle is
  // megabytes
  const [{ createHighlighterCore }, { createJavaScriptRegexEngine }] = await Promise.all([
    import('shiki/core'),
    import('shiki/engine/javascript'),
  ]);
  highlighter = await createHighlighterCore({
    themes: [import('@shikijs/themes/github-dark-dimmed')],
    langs: [...new Set(LANGS.map((l) => l.hl))].map((id) => GRAMMARS[id]()),
    engine: createJavaScriptRegexEngine(),
  });
  renderCode();
}

main();
