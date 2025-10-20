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

# ─────────────────────────────────────────────────────────────
# 1) Activity Log plugin (in-memory ring buffer)
#    - Hooks: onRequest + onSend
#    - Endpoints: GET /v2/activity, GET /v2/activity/:id, DELETE /v2/activity
# ─────────────────────────────────────────────────────────────
cat > "$PLUG/activity.js" <<'JS'
/**
 * Activity Log (in-memory)
 * - Logger muterende kall (POST/PUT/PATCH) + Idempotency-Key, duration, status
 * - GET /v2/activity?page=&pageSize=
 * - GET /v2/activity/:id
 * - DELETE /v2/activity  (x-role: admin)
 */
const BUF_MAX = 500
const store = []  // newest last
let seq = 1

function pushEntry(entry) {
  store.push(entry)
  if (store.length > BUF_MAX) store.shift()
}

export default async function activity(app) {
  app.addHook('onRequest', async (req, reply) => {
    const m = req.method
    // Log kun muterende
    if (m === 'POST' || m === 'PUT' || m === 'PATCH' || m === 'DELETE') {
      req.__act = {
        id: String(seq++),
        ts: Date.now(),
        method: m,
        url: req.url,
        role: String(req.headers['x-role'] || 'viewer'),
        idem: String(req.headers['idempotency-key'] || ''),
        body: undefined, // fylles under
        status: undefined,
        ms: undefined
      }
      // Prøv å lese body kort (uten å bremse)
      try {
        // Fastify har allerede parsed body, men her kan den være udefinert
        if (req.body != null) {
          const s = JSON.stringify(req.body)
          req.__act.body = s.length > 2000 ? s.slice(0,2000)+'…' : s
        }
      } catch {}
      req.__act.__start = process.hrtime.bigint()
    }
  })

  app.addHook('onSend', async (req, reply, payload) => {
    const ctx = req.__act
    if (!ctx) return
    try {
      const end = process.hrtime.bigint()
      const diffMs = Number(end - ctx.__start) / 1e6
      ctx.ms = Math.round(diffMs)
      ctx.status = reply.statusCode
      // Ta vare på respons (kort)
      let out = ''
      if (typeof payload === 'string') out = payload
      else if (payload && typeof payload === 'object') out = JSON.stringify(payload)
      if (out) ctx.res = out.length > 2000 ? out.slice(0,2000)+'…' : out
      delete ctx.__start
      pushEntry(ctx)
    } catch {}
    return payload
  })

  app.get('/v2/activity', async (req) => {
    const page = Number(req.query.page || 1)
    const pageSize = Number(req.query.pageSize || req.query.pagesize || 25)
    const start = Math.max(0, store.length - (page * pageSize))
    const end = Math.min(store.length, start + pageSize)
    const items = store.slice(start, end)
    return {
      ok: true,
      total: store.length,
      page, pageSize,
      items: items.slice().reverse() // nyeste først
    }
  })

  app.get('/v2/activity/:id', async (req, reply) => {
    const it = store.find(x => x.id === String(req.params.id))
    if (!it) { reply.code(404); return { ok:false, code:'not_found' } }
    return { ok:true, item: it }
  })

  app.delete('/v2/activity', async (req, reply) => {
    const role = String(req.headers['x-role'] || 'viewer')
    if (role !== 'admin') {
      reply.code(403); return { ok:false, code:'forbidden', title:'Admin role required' }
    }
    store.length = 0
    return { ok:true, cleared:true }
  })
}
JS

# ─────────────────────────────────────────────────────────────
# 2) Patch server.js to register activity (idempotent)
# ─────────────────────────────────────────────────────────────
node <<'NODE'
import fs from 'fs'
const p='apps/api/src/server.js'
let s=fs.readFileSync(p,'utf8')
if(!s.includes(`tryPlugin('activity'`)){
  const anchor = `await tryPlugin('admin-ui'`
  if (s.includes(anchor)) {
    s = s.replace(anchor, `await tryPlugin('activity', './plugins/activity.js')\n${anchor}`)
  } else {
    const listen = 'app.listen({'
    const i = s.indexOf(listen)
    const inj = `await tryPlugin('activity', './plugins/activity.js')\n`
    s = i!==-1 ? s.slice(0,i)+inj+s.slice(i) : s+'\n'+inj
  }
  fs.writeFileSync(p,s,'utf8')
  console.log('Server patched: activity plugin registered.')
} else {
  console.log('Activity plugin already registered.')
}
NODE

# ─────────────────────────────────────────────────────────────
# 3) Patch Admin UI:
#    - api() sender x-role fra localStorage (hvis satt)
#    - Ny side #/roles: vis roller og bytt aktiv rolle (lagres i localStorage)
#    - Ny side #/activity: liste + detalj + Clear
# ─────────────────────────────────────────────────────────────
node <<'NODE'
import fs from 'fs'
const f='apps/api/src/plugins/admin.ui.js'
let s=fs.readFileSync(f,'utf8')

// a) API wrapper: legg til x-role fra localStorage hvis finnes
if(!s.includes('function currentRoleHeader')){
  const add = `
function currentRoleHeader(){
  try { const r = localStorage.getItem('role'); if(r) return {'x-role': r}; } catch(e){}
  return {};
}
const api=(p,opt)=>{ 
  const baseHeaders = {"content-type":"application/json"};
  const hdr = Object.assign({}, baseHeaders, currentRoleHeader(), (opt&&opt.headers)||{});
  const final = Object.assign({}, opt||{}, { headers: hdr });
  return fetch(p, final);
};
`
  s = s.replace(/const api=\(p,opt\)=>fetch\(p,Object\.assign\(\{headers:\{"content-type":"application\/json"\}\},opt\|\|\{}\)\);/, add)
}

// b) Nav: legg til Roles + Activity (hvis mangler)
if(!s.includes('href="#/roles"')){
  s = s.replace(
    /<nav class="flex gap-2">([\s\S]*?)<\/nav>/,
    (m) => m.replace('</nav>', '<a href="#/roles" class="tag">Roles</a><a href="#/activity" class="tag">Activity</a></nav>')
  )
}

// c) Rollenormalisering (sørg for at funksjonen finnes)
if(!s.includes('function normalizeRolePayload')){
  s = s.replace('<script>(function(){', '<script>(function(){\nfunction normalizeRolePayload(j){ if(!j) return {key:"viewer"}; if(typeof j.role==="string") return {key:j.role}; if(j.role && typeof j.role==="object" && j.role.key) return {key:j.role.key}; return {key:"viewer"} }\n')
}

// d) RBAC page #/roles
if(!s.includes('function viewRoles')){
  const rolesPage = `
async function viewRoles(){
  const r = await fetch('/v2/auth/roles');
  const j = await r.json();
  const roles = j.roles||{};
  const current = (localStorage.getItem('role') || 'viewer');
  var rows='';
  Object.keys(roles).forEach(function(k){
    const v = roles[k];
    const perms = (v.permissions||[]).join(', ');
    rows += '<tr><td class="py-2 px-2">'+k+'</td><td class="py-2 px-2">'+(v.label||'')+'</td><td class="py-2 px-2 text-xs text-slate-600">'+perms+'</td></tr>';
  });
  document.getElementById('view').innerHTML =
    '<div class="mb-4 flex items-center justify-between"><h1 class="text-xl font-semibold">Roles</h1>'+
    '<div class="flex items-center gap-2 text-sm">Active role: <select id="roleSel" class="input"><option'+(current==='admin'?' selected':'')+'>admin</option><option'+(current==='viewer'?' selected':'')+'>viewer</option><option'+(current==='sales'?' selected':'')+'>sales</option><option'+(current==='warehouse'?' selected':'')+'>warehouse</option></select><button id="saveRole" class="btn btn-primary">Apply</button></div></div>'+
    '<div class="card overflow-auto"><table class="min-w-full text-sm"><thead><tr class="text-left text-slate-500"><th class="py-2 px-2">Key</th><th class="py-2 px-2">Label</th><th class="py-2 px-2">Permissions</th></tr></thead><tbody>'+rows+'</tbody></table></div>';
  document.getElementById('saveRole').onclick = function(){
    const sel = document.getElementById('roleSel');
    const val = sel.value;
    try{ localStorage.setItem('role', val) }catch(e){}
    // oppdater badge + re-render
    showRole();
    // reload current page to apply header in lists too
    location.reload();
  }
}
`
  s = s.replace(/async function router\(\)\{/, rolesPage + '\nasync function router(){')
}

// e) Activity page #/activity
if(!s.includes('function viewActivity')){
  const activityPage = `
async function viewActivity(){
  const u = new URL(location.href);
  const usp = new URLSearchParams(u.hash.split('?')[1]||'');
  const page = Number(usp.get('page')||1);
  const pageSize = Number(usp.get('pageSize')||25);
  const r = await fetch('/v2/activity?page='+page+'&pageSize='+pageSize);
  const j = await r.json();
  const list = j.items||[];
  const total = j.total||list.length;
  const pages = Math.max(1, Math.ceil(total/pageSize));
  var rows='';
  list.forEach(function(x){
    rows += '<tr><td class="py-2 px-2">'+x.id+'</td><td class="py-2 px-2">'+x.method+'</td><td class="py-2 px-2">'+x.url+'</td><td class="py-2 px-2">'+(x.idem||'')+'</td><td class="py-2 px-2">'+x.status+'</td><td class="py-2 px-2">'+x.ms+' ms</td><td class="py-2 px-2 text-right"><a class="btn btn-soft" href="#/activity/'+x.id+'">Open</a></td></tr>';
  });
  document.getElementById('view').innerHTML =
    '<div class="mb-4 flex items-center justify-between"><h1 class="text-xl font-semibold">Activity</h1>'+
    '<div class="flex items-center gap-2"><button id="clearAct" class="btn btn-soft">Clear</button></div></div>'+
    '<div class="card overflow-auto"><table class="min-w-full text-sm"><thead><tr class="text-left text-slate-500"><th class="py-2 px-2">ID</th><th class="py-2 px-2">Method</th><th class="py-2 px-2">Path</th><th class="py-2 px-2">Idempotency-Key</th><th class="py-2 px-2">Status</th><th class="py-2 px-2">Time</th><th class="py-2 px-2"></th></tr></thead><tbody>'+rows+'</tbody></table></div>'+
    '<div class="mt-4 flex items-center justify-between"><button id="actPrev" class="btn btn-soft" '+(page<=1?'disabled':'')+'>Prev</button><div class="text-sm text-slate-600">Page '+page+' of '+pages+' ('+total+')</div><button id="actNext" class="btn btn-soft" '+(page>=pages?'disabled':'')+'>Next</button></div>';
  const prev=document.getElementById('actPrev'); if(prev) prev.onclick=function(){ if(page>1) location.hash = '#/activity?page='+(page-1)+'&pageSize='+pageSize }
  const next=document.getElementById('actNext'); if(next) next.onclick=function(){ if(page<pages) location.hash = '#/activity?page='+(page+1)+'&pageSize='+pageSize }
  const clr=document.getElementById('clearAct'); if(clr) clr.onclick=async function(){
    const res = await fetch('/v2/activity', { method:'DELETE', headers: {'x-role': (localStorage.getItem('role')||'viewer')} })
    const j = await res.json(); (window.notice||function(){})((j.ok?'Cleared':'Failed clear'), j.ok); if(j.ok) location.reload();
  }
}
async function viewActivityItem(id){
  const r = await fetch('/v2/activity/'+id); const j = await r.json(); const x=j.item||{};
  const pretty = (obj)=>{ try{ return JSON.stringify(obj,null,2) } catch(e){ return String(obj) } }
  document.getElementById('view').innerHTML =
    '<div class="mb-4 flex items-center justify-between"><h1 class="text-xl font-semibold">Activity #'+(x.id||id)+'</h1><a class="btn btn-soft" href="#/activity">Back</a></div>'+
    '<div class="grid md:grid-cols-2 gap-4">'+
      '<div class="card"><div class="font-semibold mb-2">Summary</div>'+
        '<div class="text-sm">Method: <b>'+(x.method||'')+'</b></div>'+
        '<div class="text-sm">Path: <code>'+(x.url||'')+'</code></div>'+
        '<div class="text-sm">Role: '+(x.role||'')+'</div>'+
        '<div class="text-sm">Idempotency-Key: <code>'+(x.idem||'')+'</code></div>'+
        '<div class="text-sm">Status: '+(x.status||'')+'</div>'+
        '<div class="text-sm">Time: '+(x.ms||'?')+' ms</div>'+
      '</div>'+
      '<div class="card"><div class="font-semibold mb-2">Request Body</div><pre class="text-xs whitespace-pre-wrap">'+(x.body||'')+'</pre></div>'+
      '<div class="card md:col-span-2"><div class="font-semibold mb-2">Response (truncated)</div><pre class="text-xs whitespace-pre-wrap">'+(x.res||'')+'</pre></div>'+
    '</div>';
}
`
  s = s.replace(/async function router\(\)\{/, activityPage + '\nasync function router(){')
}

// f) Router cases
if(!s.includes('if(route===\'roles\')')) {
  s = s.replace(
`if(route==='products') return viewProducts();
    if(route==='product') return viewProduct(decodeURIComponent(arg||'TEST'));
    if(route==='orders') return viewOrders();
    if(route==='order') return viewOrder(arg||'1');
    if(route==='flags') return viewFlags();
    return viewOrders();`,
`if(route==='products') return viewProducts();
    if(route==='product') return viewProduct(decodeURIComponent(arg||'TEST'));
    if(route==='orders') return viewOrders();
    if(route==='order') return viewOrder(arg||'1');
    if(route==='flags') return viewFlags();
    if(route==='roles') return viewRoles();
    if(route==='activity') { if(arg) return viewActivityItem(arg); return viewActivity(); }
    return viewOrders();`)
}

fs.writeFileSync(f,s,'utf8')
console.log('Admin UI patched: RBAC page + Activity page + role header propagation.')
NODE

# ─────────────────────────────────────────────────────────────
# 4) Restart & smoke
# ─────────────────────────────────────────────────────────────
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 2
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "📒 Activity (page1):"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/activity?page=1&pageSize=5" || true; echo
echo "🖥️ Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin#/roles"
