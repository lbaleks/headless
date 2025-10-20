#!/usr/bin/env bash
set -euo pipefail

SRV="apps/api/src/server.js"
PLUG_IMPORT="import variantsCreate from './plugins/variants.create.js'"
PLUG_REGISTER="await app.register(variantsCreate)"

if [ ! -f "$SRV" ]; then
  echo "Fant ikke $SRV"; exit 1
fi

# 1) Legg til import og register i server.js hvis de mangler (med Node for å tåle macOS/BSD sed)
node - <<'NODE'
const fs = require('fs');
const path = 'apps/api/src/server.js';
let s = fs.readFileSync(path, 'utf8');

if (!s.includes("import variantsCreate from './plugins/variants.create.js'")) {
  // Sett import nær toppen (etter andre imports)
  s = s.replace(/(import [^\n]+;\s*)+(?=\n)/, m => m + "import variantsCreate from './plugins/variants.create.js'\n");
}

if (!s.includes('await app.register(variantsCreate)')) {
  // Forsøk å plassere rett før app.listen(...). Hvis ikke finnes, legg før siste linje.
  if (s.includes('app.listen(')) {
    s = s.replace(/(?=\n\s*app\.listen\()/, "\nawait app.register(variantsCreate)\n");
  } else {
    s = s + "\nawait app.register(variantsCreate)\n";
  }
}

fs.writeFileSync(path, s, 'utf8');
console.log('Patched server.js (variantsCreate)');
NODE

# 2) Restart API
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
: > .api.dev.log
( cd apps/api && nohup npm run start > ../../.api.dev.log 2>&1 & echo $! > ../../.api.pid )
sleep 1.4

echo "🩺 Health:"
curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "🧭 Routes (grep variants):"
curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/debug/routes" | sed -n '/variants/p' || true
echo
echo "🧪 Probe bootstrap endpoint:"
curl -sS -X POST "http://127.0.0.1:$PORT/v2/integrations/magento/variants/bootstrap?from=TEST&cfg=TEST-CFG&attr=size" | jq -c . || true
