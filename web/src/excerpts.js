// The code panel shows each port's own hot loop, read from its sources at
// build time: every port marks one excerpt per scene between a line holding
// `@excerpt <SCENE>` and a line holding `@end`. A scene with an optimisation
// ladder also marks each earlier rung as `@excerpt <SCENE>/<k>`.

// Port sources live in ports/<lang>/; the language is the directory name.
const portFiles = import.meta.glob(
  [
    '../../ports/*/**/*.{c,h,cpp,hpp,rs,zig,js,mjs,ts,py,pl,pm,lua,rb,wat,sql,glsl,frag}',
    '!../../ports/*/**/node_modules/**',
    '!../../ports/*/target/**',
    '!../../ports/*/zig-out/**',
    '!../../ports/*/.zig-cache/**',
    '!../../ports/*/vendor/**',
  ],
  { query: '?raw', import: 'default', eager: true },
);

const sources = { go: import.meta.glob('../../go/internal/fx/*.go', { query: '?raw', import: 'default', eager: true }) };
for (const [path, text] of Object.entries(portFiles)) {
  const lang = path.split('/')[3];
  (sources[lang] ??= {})[path] = text;
}


function extract(files) {
  const out = {};
  for (const [path, text] of Object.entries(files)) {
    const lines = text.split('\n');
    let scene = null;
    let body = [];
    let at = 0;
    lines.forEach((line, i) => {
      const m = line.match(/@excerpt\s+([A-Z]+(?:\/\d+)?)/);
      if (m) {
        scene = m[1];
        body = [];
        at = i + 2;
      } else if (scene && /@end\b/.test(line)) {
        out[scene] = { code: dedent(body), file: path.replace(/^(\.\.\/)+/, ''), line: at };
        scene = null;
      } else if (scene) {
        body.push(line);
      }
    });
  }
  return out;
}

function dedent(lines) {
  const expanded = lines.map((l) => l.replace(/\t/g, '    '));
  const indents = expanded.filter((l) => l.trim()).map((l) => l.match(/^ */)[0].length);
  const cut = indents.length ? Math.min(...indents) : 0;
  return expanded.map((l) => l.slice(cut)).join('\n').replace(/\s+$/, '');
}

export const EXCERPTS = Object.fromEntries(
  Object.entries(sources).map(([lang, files]) => [lang, extract(files)]),
);

// Each port's NOTES.md has one bullet per scene, `- **SCENE**: text`, on how
// that language approaches it differently from Go. The lab shows the bullet
// above the excerpt.
const notes = import.meta.glob('../../ports/*/NOTES.md', { query: '?raw', import: 'default', eager: true });

export const NOTES = {};
for (const [path, text] of Object.entries(notes)) {
  const lang = path.split('/').at(-2);
  const out = (NOTES[lang] = {});
  let scene = null;
  for (const line of text.split('\n')) {
    const m = line.match(/^- \*\*([A-Z]+(?:\/\d+)?)\*\*:\s*(.*)$/);
    if (m) {
      scene = m[1];
      out[scene] = m[2];
    } else if (scene && /^\s{2,}\S/.test(line)) {
      out[scene] += ' ' + line.trim();
    } else {
      scene = null;
    }
  }
}
