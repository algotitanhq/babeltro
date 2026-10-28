#!/usr/bin/env node
// og writes one page per effect into web/dist (dist/plasma/index.html…), each
// with its own link-preview tags and a 1200x630 preview image drawn by the C
// port itself, so a link to an effect shows that effect wherever it is
// shared. The app stays a single page: these files are index.html with other
// <meta> tags, and the router reads the address.
//
//   node tools/og.mjs        (after vite build; `npm run build` does both)

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'web/dist');
const SITE = 'https://babeltro.storagebits.workers.dev';
const W = 1200;
const H = 630;

const { fromWasm } = await import(pathToFileURL(join(root, 'web/src/host/ports.js')).href);
const { EFFECTS, LANGS } = await import(pathToFileURL(join(root, 'web/src/content.js')).href);

// the frame each preview shows: far enough in for the stateful scenes
const AT = { STARFIELD: 120, FIRE: 240, MANDELBROT: 200, FINALE: 90 };
// the finale draws its own text at the bottom, so its caption goes on top
const ON_TOP = new Set(['FINALE']);
const FONT = '/System/Library/Fonts/SFNSMono.ttf';
const BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf';

const c = await fromWasm(readFileSync(join(root, 'web/public/wasm/c.wasm')), () => {});
c.init(W, H);

const html = readFileSync(join(dist, 'index.html'), 'utf8');
const esc = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
// replace the content of one meta tag, by property or name
const meta = (page, key, value) =>
  page.replace(new RegExp(`(<meta (?:property|name)="${key}" content=")[^"]*(")`), `$1${esc(value)}$2`);

mkdirSync(join(dist, 'og'), { recursive: true });
const count = LANGS.length;

for (const [i, e] of EFFECTS.entries()) {
  const slug = e.name.toLowerCase();
  c.start(i);
  for (let n = 1; n <= (AT[e.name] ?? 120); n++) c.render(n);
  const raw = join(dist, 'og', `${slug}.rgba`);
  const fb = c.pixels();
  writeFileSync(raw, Buffer.from(fb.buffer, fb.byteOffset, W * H * 4));

  // the effect, a dark band at the bottom, its name and the question
  const png = join(dist, 'og', `${slug}.png`);
  const top = ON_TOP.has(e.name);
  execFileSync('magick', [
    '-size', `${W}x${H}`, '-depth', '8', `rgba:${raw}`,
    '(', '-size', `${W}x230`, top ? 'gradient:#0b0a10f2-#0b0a1000' : 'gradient:#0b0a1000-#0b0a10f2', ')',
    '-gravity', top ? 'north' : 'south', '-composite',
    // on top, the caption sits left of the finale's centred logo, smaller
    ...(top ? ['-gravity', 'northwest'] : []),
    '-font', BOLD, '-fill', '#ffffff', '-pointsize', top ? '54' : '76', '-annotate', top ? '+36+40' : '+0+92', e.name,
    '-font', FONT, '-fill', '#e8e4f2', '-pointsize', top ? '24' : '30',
    '-annotate', top ? '+38+110' : '+0+40', top ? `How do you make it\nin ${count} languages?` : `How do you make it in ${count} languages?`,
    '-gravity', top ? 'southwest' : 'northwest', '-fill', '#ffffffcc', '-pointsize', '26', '-annotate', '+28+22', 'BABELTRO',
    '-strip', png,
  ]);
  execFileSync('rm', [raw]);

  const title = `${e.name} · babeltro`;
  const desc = `${e.text} In ${count} languages, live in your browser, pixel-identical.`;
  let page = html.replace(/<title>[^<]*<\/title>/, `<title>${esc(e.name.toLowerCase())} · babeltro</title>`);
  page = meta(page, 'description', desc);
  page = meta(page, 'og:title', title);
  page = meta(page, 'og:description', desc);
  page = meta(page, 'og:url', `${SITE}/${slug}`);
  page = meta(page, 'og:image', `${SITE}/og/${slug}.png`);
  page = meta(page, 'og:image:alt', `${e.name}, a demoscene effect, as drawn by babeltro's C port`);
  page = meta(page, 'twitter:title', title);
  page = meta(page, 'twitter:description', desc);
  page = meta(page, 'twitter:image', `${SITE}/og/${slug}.png`);
  mkdirSync(join(dist, slug), { recursive: true });
  writeFileSync(join(dist, slug, 'index.html'), page);
  console.log(`${slug}: page and preview`);
}
