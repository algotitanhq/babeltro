import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';

// The lab reads the ports' sources (for the code panel) and the JavaScript
// port itself from outside web/, so the dev server must be allowed there.
const repo = fileURLToPath(new URL('..', import.meta.url));

export default defineConfig({
  server: { fs: { allow: [repo] } },
  worker: { format: 'es' },
});
