#!/usr/bin/env bash
set -euo pipefail
UI="apps/api/src/plugins/admin.ui.js"
LOG=".api.dev.log"
PIDF=".api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

node <<'NODE'
import fs from 'fs'
const f='apps/api/src/plugins/admin.ui.js'
let s=fs.readFileSync(f,'utf8')

// 1) Global fetch-interceptor (idempotent)
if (!s.includes('/* RBAC FETCH INTERCEPTOR */')) {
  s = s.replace(
    '<script>(function(){',
    `<script>(function(){
/* RBAC FETCH INTERCEPTOR */
try{
  const __origFetch = window.fetch.bind(window);
  window.fetch = (input, init={})=>{
    try{
      const url = (typeof input==='string') ? input : (input && input.url) || '';
      if (url.startsWith('/v2/')) {
        const hdr = new Headers(init.headers || {});
        if (!hdr.has('x-role')) {
          const role = localStorage.getItem('role') || 'viewer';
          hdr.set('x-role', role);
        }
        init = Object.assign({}, init, { headers: hdr });
      }
    }catch(e){}
    return __origFetch(input, init);
  };
}catch(e){}
`
  )
}

// 2) showRole(): sett badge fra localStorage først, så bekreft med whoami
s = s.replace(/async function showRole\([\s\S]*?\}\n\}/, `
async function showRole(){
  // 2a) Sett badge direkte fra localStorage
  try {
    const local = (localStorage.getItem('role') || 'viewer');
    const tag = document.getElementById('roleTag');
    if(tag){ tag.textContent = local; }
    if(local !== 'admin'){
      document.querySelectorAll('.btn-primary').forEach(b=>{ b.disabled = true; b.classList.add('opacity-60','cursor-not-allowed'); });
    } else {
      document.querySelectorAll('.btn-primary').forEach(b=>{ b.disabled = false; b.classList.remove('opacity-60','cursor-not-allowed'); });
    }
  } catch(e){}

  // 2b) Bekreft fra server (nå vil header være på via fetch-interceptor)
  try {
    const r = await fetch('/v2/auth/whoami');
    const j = await r.json();
    const info = (typeof normalizeRolePayload==='function') ? normalizeRolePayload(j) : {key:(j&&j.role)||'viewer'};
    const tag = document.getElementById('roleTag');
    if(tag){ tag.textContent = info.key || 'viewer'; }
    if(info.key !== 'admin'){
      document.querySelectorAll('.btn-primary').forEach(b=>{ b.disabled = true; b.classList.add('opacity-60','cursor-not-allowed'); });
    } else {
      document.querySelectorAll('.btn-primary').forEach(b=>{ b.disabled = false; b.classList.remove('opacity-60','cursor-not-allowed'); });
    }
  } catch(e){
    // behold local fallback
    console.warn('whoami failed', e);
  }
}
`)

// 3) Sørg for at showRole kalles etter router()
s = s.replace(/router\(\);\s*<\/script>/, 'router(); showRole();\n</script>')

fs.writeFileSync(f,s,'utf8')
console.log('Admin UI patched: fetch-interceptor + instant role badge.')
NODE

# Restart
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
: > "$LOG"
( cd apps/api && nohup npm run start > "../../$LOG" 2>&1 & echo $! > "../../$PIDF" )
sleep 1.5
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "🖥️ Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin"
