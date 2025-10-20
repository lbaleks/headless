#!/usr/bin/env bash
set -euo pipefail
SV="apps/api/src/server.js"
TMP="$(mktemp)"

# Les server.js
node - <<'NODE'
const fs = require('fs');
const p = 'apps/api/src/server.js';
let s = fs.readFileSync(p,'utf8');

// Fjern eventuell statisk import-linje for adminUi
s = s.replace(/^\s*import\s+adminUi\s+from\s+'\.\/plugins\/admin\.ui\.js';?\s*$/m, '');

// Sett inn robust, dynamisk import rett før første "app.listen("
const anchor = 'app.listen({ port:';
if (!s.includes("dynamic-admin-ui")) {
  const inj = `
/* dynamic-admin-ui */ 
try {
  const mod = await import('./plugins/admin.ui.js');
  if (mod && mod.default) {
    await app.register(mod.default);
    app.log.info('admin.ui registered');
  } else {
    app.log.warn('admin.ui module missing default export');
  }
} catch (e) {
  app.log.warn({ err: String(e) }, 'admin.ui registration failed (continuing)');
}
/* /dynamic-admin-ui */
`.trim();

  const i = s.indexOf(anchor);
  if (i !== -1) {
    s = s.slice(0, i) + inj + '\n' + s.slice(i);
  } else {
    // fallback: append at end
    s += '\n' + inj + '\n';
  }
}

fs.writeFileSync(p, s, 'utf8');
console.log('Patched server.js (robust admin-ui import)');
NODE
