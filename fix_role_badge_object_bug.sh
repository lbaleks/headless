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

// 1) Robust extractor for role fra whoami-respons
if(!s.includes('function roleKeyFromPayload')){
  s = s.replace('<script>(function(){', `<script>(function(){
function roleKeyFromPayload(j){
  try{
    if(!j) return 'viewer';
    // vanlige former: { ok:true, role:'admin' } ELLER { ok:true, role:{ key:'admin', label:'…' } }
    const r = j.role;
    if (typeof r === 'string') return r;
    if (r && typeof r === 'object') {
      if (typeof r.key === 'string') return r.key;
      if (typeof r.name === 'string') return r.name;
      if (typeof r.label === 'string') return r.label.toLowerCase();
    }
    // fallback hvis noen returnerer { key:'admin' } på toppnivå
    if (typeof j.key === 'string') return j.key;
    return 'viewer';
  }catch(e){ return 'viewer'; }
}
`)
}

// 2) showRole: bruk roleKeyFromPayload og ikke sett objekter som tekst
s = s.replace(/async function showRole\([\s\S]*?\}\n\}/, `
async function showRole(){
  // sett badge fra localStorage som rask feedback
  let local = 'viewer';
  try { local = localStorage.getItem('role') || 'viewer'; } catch(e){}
  const tag = document.getElementById('roleTag');
  if(tag){ tag.textContent = local; }

  const applyBtns = (role)=>{
    const isAdmin = role === 'admin';
    document.querySelectorAll('.btn-primary').forEach(b=>{
      b.disabled = !isAdmin;
      b.classList.toggle('opacity-60', !isAdmin);
      b.classList.toggle('cursor-not-allowed', !isAdmin);
    });
  };
  applyBtns(local);

  // verifiser med whoami (nå har vi fetch-interceptor som legger på x-role)
  try{
    const r = await fetch('/v2/auth/whoami');
    const j = await r.json();
    const serverRole = roleKeyFromPayload(j);
    if(tag){ tag.textContent = serverRole; }
    applyBtns(serverRole);
  }catch(e){
    // behold local fallback
    console.warn('whoami failed', e);
  }
}
`)

// 3) Sørg for at vi kaller showRole etter router()
s = s.replace(/router\(\);\s*<\/script>/, 'router(); showRole();\n</script>')

fs.writeFileSync(f,s,'utf8')
console.log('Patched: roleKeyFromPayload + safe badge update.')
NODE

# restart
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
: > "$LOG"
( cd apps/api && nohup npm run start > "../../$LOG" 2>&1 & echo $! > "../../$PIDF" )
sleep 1.5
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "🖥️ Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin"
