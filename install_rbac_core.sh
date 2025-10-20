#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
API="$ROOT/apps/api"
PLUG="$API/src/plugins"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

mkdir -p "$PLUG"

# 1) rbac plugin
cat > "$PLUG/rbac.js" <<'JS'
/**
 * Simple Role-Based Access Control plugin
 * - GET /v2/auth/whoami   -> identifies current role
 * - GET /v2/auth/roles     -> available roles
 */
const ROLES = {
  admin: { label: 'Administrator', permissions: ['*'] },
  viewer: { label: 'Viewer', permissions: ['read'] },
  sales: { label: 'Sales', permissions: ['orders:view','orders:invoice'] },
  warehouse: { label: 'Warehouse', permissions: ['msi:view','msi:update'] }
}

export default async function rbac(app) {
  app.get('/v2/auth/roles', async () => ({ ok: true, roles: ROLES }))
  app.get('/v2/auth/whoami', async (req) => {
    const h = req.headers || {}
    const role = (h['x-role'] || 'viewer').toString().toLowerCase()
    const info = ROLES[role] ? { key: role, ...ROLES[role] } : { key: 'viewer', ...ROLES.viewer }
    return { ok: true, role: info }
  })
}
JS

# 2) Patch admin.ui.js (legg til visning av rolle i header)
node <<'NODE'
import fs from 'fs'
const f='apps/api/src/plugins/admin.ui.js'
let s=fs.readFileSync(f,'utf8')
if(!s.includes('id="roleTag"')){
  s=s.replace('<div class="font-semibold">Litebrygg Admin</div>',
    '<div class="font-semibold flex items-center gap-2">Litebrygg Admin <span id="roleTag" class="tag bg-slate-700 text-white text-xs px-2">…</span></div>')
}
if(!s.includes('async function showRole')){
  const block=`
async function showRole(){
  try {
    const r = await fetch('/v2/auth/whoami');
    const j = await r.json();
    const tag = document.getElementById('roleTag');
    if(tag && j.role && j.role.key){
      tag.textContent = j.role.key;
      if(j.role.key!=='admin'){
        document.querySelectorAll('.btn-primary').forEach(b=>b.disabled=true);
      }
    }
  } catch(e){ console.warn('whoami failed', e) }
}
`;
  s=s.replace(/addEventListener\('hashchange', router\); router\(\);/, block+'\naddEventListener(\'hashchange\', router); router(); showRole();')
}
fs.writeFileSync(f,s,'utf8')
console.log('RBAC tag + role fetch added to UI.')
NODE

# 3) Restart
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 2
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true
echo
echo "👤 Whoami:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/auth/whoami" || true
echo
echo "🖥️ Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin"
