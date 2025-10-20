#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
API="$ROOT/apps/api"
SV="$API/src/server.js"
UI="$API/src/plugins/admin.ui.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

# 1) Sørg for at rbac-plugin finnes (fra forrige steg)
if [ ! -f "$API/src/plugins/rbac.js" ]; then
  cat > "$API/src/plugins/rbac.js" <<'JS'
const ROLES = {
  admin: { label: 'Administrator', permissions: ['*'] },
  viewer: { label: 'Viewer', permissions: ['read'] },
  sales: { label: 'Sales', permissions: ['orders:view','orders:invoice'] },
  warehouse: { label: 'Warehouse', permissions: ['msi:view','msi:update'] }
}
export default async function rbac(app) {
  app.get('/v2/auth/roles', async () => ({ ok: true, roles: ROLES }))
  app.get('/v2/auth/whoami', async (req) => {
    const roleKey = String((req.headers['x-role']||'viewer')).toLowerCase()
    const roleObj = ROLES[roleKey] ? { key: roleKey, ...ROLES[roleKey] } : { key:'viewer', ...ROLES.viewer }
    return { ok: true, role: roleObj }
  })
}
JS
fi

# 2) Registrer rbac i server.js (robust dynamic import-list)
node <<'NODE'
import fs from 'fs'
const p='apps/api/src/server.js'
let s=fs.readFileSync(p,'utf8')
if(!s.includes(`tryPlugin('rbac'`)){
  // Sett inn rbac rett før admin-ui-registreringen hvis mulig
  s = s.replace(
    /await tryPlugin\('admin-ui'[\s\S]*?\);\n/,
    `await tryPlugin('rbac', './plugins/rbac.js')\n$&`
  )
  // Hvis ikke fant vi admin-ui-linjen, bare append på slutten før listen
  if(!s.includes(`tryPlugin('rbac'`)){
    const anchor = 'app.listen({ port:'
    const i = s.indexOf(anchor)
    const inj = `await tryPlugin('rbac', './plugins/rbac.js')\n`
    s = i!==-1 ? s.slice(0,i)+inj+s.slice(i) : s+'\n'+inj
  }
  fs.writeFileSync(p,s,'utf8')
  console.log('Server patched: rbac plugin registered.')
} else {
  console.log('Server already has rbac registration.')
}
NODE

# 3) Gjør UI robust: støtt både {role:"viewer"} og {role:{key:"viewer"}}
node <<'NODE'
import fs from 'fs'
const f='apps/api/src/plugins/admin.ui.js'
let s=fs.readFileSync(f,'utf8')

if(!s.includes('normalizeRole(')){
  const normalizeFn = `
function normalizeRolePayload(j){
  // støtt både { role:"viewer" } og { role:{ key:"viewer" } }
  if (!j) return { key: 'viewer' }
  if (typeof j.role === 'string') return { key: j.role }
  if (j.role && typeof j.role === 'object' && j.role.key) return { key: j.role.key }
  return { key: 'viewer' }
}
`
  s = s.replace(/<script>\(function\(\)\{/, `<script>(function(){\n${normalizeFn}`)
}

s = s.replace(/async function showRole\([\s\S]*?\}\n\}\n/, // replace existing showRole if present
`async function showRole(){
  try {
    const r = await fetch('/v2/auth/whoami');
    const j = await r.json();
    const info = normalizeRolePayload(j);
    const tag = document.getElementById('roleTag');
    if(tag){ tag.textContent = info.key || 'viewer'; }
    // Deaktiver "primær" admin-aksjoner om ikke admin
    if(info.key !== 'admin'){
      document.querySelectorAll('.btn-primary').forEach(b=>{ b.disabled = true; b.classList.add('opacity-60','cursor-not-allowed'); });
    }
  } catch(e){ console.warn('whoami failed', e) }
}
`)

fs.writeFileSync(f,s,'utf8')
console.log('Admin UI patched: role normalization + button gating.')
NODE

# 4) Restart
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 2
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "👤 Whoami (objekt):"; curl -sS --max-time 6 -H 'x-role: admin' http://127.0.0.1:$PORT/v2/auth/whoami || true; echo
echo "👤 Whoami (viewer):"; curl -sS --max-time 6 -H 'x-role: viewer' http://127.0.0.1:$PORT/v2/auth/whoami || true; echo
echo "🖥️ Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin"
