#!/usr/bin/env bash
set -euo pipefail
API="apps/api"
UI="$API/src/plugins/admin.ui.js"
LOG=".api.dev.log"
PIDF=".api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

node <<'NODE'
import fs from 'fs'
const f='apps/api/src/plugins/admin.ui.js'
let s=fs.readFileSync(f,'utf8')

// 1) Sørg for roleTag i header
if(!s.includes('id="roleTag"')){
  s = s.replace(
    '<div class="font-semibold">',
    '<div class="font-semibold flex items-center gap-2">Litebrygg Admin <span id="roleTag" class="tag bg-slate-700 text-white text-xs px-2">…</span></div><!--'
  )
  s = s.replace('Litebrygg Admin', 'Litebrygg Admin') // no-op, bare sikre kontekst
}

// 2) Legg inn normalizeRolePayload hvis mangler
if(!s.includes('function normalizeRolePayload')){
  const fn = `
function normalizeRolePayload(j){
  // støtt både { role:"viewer" } og { role:{ key:"viewer" } }
  if (!j) return { key: 'viewer' }
  if (typeof j.role === 'string') return { key: j.role }
  if (j.role && typeof j.role === 'object' && j.role.key) return { key: j.role.key }
  return { key: 'viewer' }
}
`
  s = s.replace('<script>(function(){', '<script>(function(){\n'+fn)
}

// 3) Erstatt showRole med robust versjon
if(s.includes('async function showRole')){
  s = s.replace(/async function showRole\([\s\S]*?\}\n\}/, `
async function showRole(){
  try {
    const r = await fetch('/v2/auth/whoami');
    const j = await r.json();
    const info = normalizeRolePayload(j);
    const tag = document.getElementById('roleTag');
    if(tag){ tag.textContent = info.key || 'viewer'; }
    if(info.key !== 'admin'){
      document.querySelectorAll('.btn-primary').forEach(b=>{ b.disabled = true; b.classList.add('opacity-60','cursor-not-allowed'); });
    }
  } catch(e){
    // fallback: vis viewer i taggen, ikke (…) 
    const tag = document.getElementById('roleTag');
    if(tag){ tag.textContent = 'viewer'; }
    console.warn('whoami failed', e)
  }
}
`)
} else {
  s = s.replace('addEventListener(\'hashchange\', router);', `
async function showRole(){
  try {
    const r = await fetch('/v2/auth/whoami');
    const j = await r.json();
    const info = normalizeRolePayload(j);
    const tag = document.getElementById('roleTag');
    if(tag){ tag.textContent = info.key || 'viewer'; }
    if(info.key !== 'admin'){
      document.querySelectorAll('.btn-primary').forEach(b=>{ b.disabled = true; b.classList.add('opacity-60','cursor-not-allowed'); });
    }
  } catch(e){
    const tag = document.getElementById('roleTag');
    if(tag){ tag.textContent = 'viewer'; }
    console.warn('whoami failed', e)
  }
}
addEventListener('hashchange', router);
`)
}

// 4) Sørg for at showRole kalles etter første render
s = s.replace(/router\(\);\s*<\/script>/, 'router(); showRole();\n</script>')

fs.writeFileSync(f,s,'utf8')
console.log('Admin UI: role normalizer + robust showRole patched.')
NODE

# Restart
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
: > "$LOG"
( cd apps/api && nohup npm run start > "../../$LOG" 2>&1 & echo $! > "../../$PIDF" )
sleep 1.5
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "🖥️ Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin"
