// The code panel shows each port's own hot loop, read from its sources at
// build time: every port marks one excerpt per scene between a line holding
// `@excerpt <SCENE>` and a line holding `@end`.

const sources = {
  go: import.meta.glob('../../go/internal/fx/*.go', { query: '?raw', import: 'default', eager: true }),
  c: import.meta.glob('../../c/**/*.c', { query: '?raw', import: 'default', eager: true }),
  rust: import.meta.glob('../../rust/src/**/*.rs', { query: '?raw', import: 'default', eager: true }),
  js: import.meta.glob('../../js/**/*.js', { query: '?raw', import: 'default', eager: true }),
};

function extract(files) {
  const out = {};
  for (const [path, text] of Object.entries(files)) {
    const lines = text.split('\n');
    let scene = null;
    let body = [];
    let at = 0;
    lines.forEach((line, i) => {
      const m = line.match(/@excerpt\s+([A-Z]+)/);
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
