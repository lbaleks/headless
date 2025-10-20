#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
PLUG="$API/src/plugins"
SV="$API/src/server.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

mkdir -p "$PLUG"

# 1) Oppdater feature-flags plugin: GET + PUT (admin kreves for PUT)
cat > "$PLUG/feature-flags.js" <<'JS'
/**
 * Feature flags (volatile in-memory)
 * - GET /v2/feature-flags -> { ok, flags }
 * - PUT /v2/feature-flags  (x-role: admin)
 *      body: { flags: { key: boolean, ... } }
 */
const FLAGS = {
  m2_products: true,
  m2_mutations: true,
  m2_customers: true,
  m2_orders: true,
  m2_categories: true,
  m2_sales_rules: true,
  m2_creditmemos: true,
  m2_invoices: true,
  m2_msi: true,
  rbac: true,
  openapi: true,
  m2_credit_helper: true
}

export default async function featureFlagsPlugin (app) {
  app.get('/v2/feature-flags', async () => ({ ok: true, flags: FLAGS }))

  app.put('/v2/feature-flags', async (req, reply) => {
    const role = req.headers['x-role']
    if (role !== 'admin') {
      reply.code(403)
      return { ok: false, code: 'forbidden', title: 'Admin role required' }
    }
    const body = req.body || {}
    const incoming = body.flags || {}
    let changed = {}
    for (const k of Object.keys(incoming)) {
      if (Object.prototype.hasOwnProperty.call(FLAGS, k)) {
        const v = incoming[k]
        const bool = v === true || v === false || v === 1 || v === 0 || v === 'true' || v === 'false'
        if (bool) {
          const next = (v === true || v === 1 || v === 'true')
          if (FLAGS[k] !== next) {
            FLAGS[k] = next
            changed[k] = next
          }
        }
      }
    }
    return { ok: true, changed, flags: FLAGS }
  })
}
JS

# 2) Patch admin.ui.js: legg til "Feature Flags" side med toggles
UI="$PLUG/admin.ui.js"
if [ -f "$UI" ]; then
  node <<'NODE'
import fs from 'fs'
const f = 'apps/api/src/plugins/admin.ui.js'
let s = fs.readFileSync(f,'utf8')

// a) Sett inn nav-link om den ikke finnes
if (!s.includes('href="#/flags"')) {
  s = s.replace(
    /<nav class="flex gap-2">([\s\S]*?)<\/nav>/,
    (m) => m.replace('</nav>', '<a href="#/flags" class="tag">Feature Flags</a></nav>')
  )
}

// b) Legg til viewFlags() om den ikke finnes
if (!s.includes('function viewFlags')) {
  const viewFlagsFn = `
async function viewFlags(){
  const r = await fetch('/v2/feature-flags');
  const j = await r.json();
  const flags = j.flags || {};
  var rows = '';
  Object.keys(flags).sort().forEach(function(k){
    var checked = flags[k] ? 'checked' : '';
    rows += '<tr><td class="py-2 px-2">'+k+'</td><td class="py-2 px-2"><label class="inline-flex items-center gap-2"><input type="checkbox" data-flag="'+k+'" '+checked+'/><span class="tag">'+(flags[k]?'on':'off')+'</span></label></td></tr>';
  });
  document.getElementById('view').innerHTML =
    '<div class="mb-4 flex items-center justify-between"><h1 class="text-xl font-semibold">Feature Flags</h1><div class="text-xs text-slate-500">Endringer krever admin</div></div>'+
    '<div class="card overflow-auto"><table class="min-w-full text-sm"><thead><tr class="text-left text-slate-500"><th class="py-2 px-2">Flag</th><th class="py-2 px-2">Value</th></tr></thead><tbody>'+rows+'</tbody></table></div>'+
    '<div class="mt-3 text-xs text-slate-500">Toggle sender PUT /v2/feature-flags med <code>x-role: admin</code></div>';

  // bind toggles
  Array.from(document.querySelectorAll('input[type="checkbox"][data-flag]')).forEach(function(el){
    el.addEventListener('change', async function(){
      const key = el.getAttribute('data-flag');
      const val = el.checked;
      const payload = { flags: { [key]: val } };
      const res = await fetch('/v2/feature-flags', {
        method: 'PUT',
        headers: { 'content-type': 'application/json', 'x-role': 'admin' },
        body: JSON.stringify(payload)
      });
      const jr = await res.json();
      const ok = jr && jr.ok === true;
      const tag = el.parentElement.querySelector('.tag');
      if (tag) tag.textContent = val ? 'on' : 'off';
      (window.showNotice||function(){})((ok?'Updated ':'Failed ')+key+': '+val, ok);
    })
  });
}
`;
  // Sett inn før router()
  s = s.replace(/async function router\(\)\{/, viewFlagsFn + '\nasync function router(){')
}

// c) Ruter: legg til case for #/flags
if (!s.includes('if(route==="flags")')) {
  s = s.replace(
    /if\(route==="products"\)[\s\S]*?return viewOrders\(\);/,
`if(route==="products") return viewProducts();
    if(route==="product") return viewProduct(decodeURIComponent(arg||"TEST"));
    if(route==="orders") return viewOrders();
    if(route==="order") return viewOrder(arg||"1");
    if(route==="flags") return viewFlags();
    return viewOrders();`
  )
}

fs.writeFileSync(f, s, 'utf8')
console.log('Admin UI patched with Feature Flags page.')
NODE
else
  echo "WARN: $UI not found. Skipping UI patch."
fi

# 3) Restart
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1.5
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true
echo
echo "⚙️ Flags (GET):"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/feature-flags" || true
echo
echo "🖥️ Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin#/flags"
