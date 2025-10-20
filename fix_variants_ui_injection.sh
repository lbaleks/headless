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

// 1) Legg til non-invasive postRender-hook etter router()
if(!s.includes('function postRenderVariantsFix')){
  s = s.replace(/router\(\);\s*showRole\(\);\s*<\/script>/, `router(); showRole(); postRenderVariantsFix();
</script>`)

  // hvis ikke fant exact, forsøk bare å sikre at vi kaller den minst en gang
  if(!s.includes('postRenderVariantsFix();')){
    s = s.replace(/router\(\);\s*<\/script>/, `router(); postRenderVariantsFix();
</script>`)
  }

  // 2) Selve fallbacken: finner sku på produktsiden og injiserer/oppdaterer variants-boks
  s = s.replace('</body>', `
<script>
function currentRouteParts(){
  var h = location.hash || '#/orders';
  var p = h.split('/');
  // #/product/<SKU>
  return { route: p[1]||'', arg: p[2]||'' }
}
async function fetchVariantsForSku(sku){
  try{
    const r = await fetch('/v2/integrations/magento/products/'+encodeURIComponent(sku)+'/variants');
    return await r.json();
  }catch(e){ return { ok:false, items:[], source:'error' } }
}
function ensureVariantsBox(){
  let box = document.getElementById('variantsBox');
  if(!box){
    const anchor = document.getElementById('productMeta') || document.getElementById('view');
    box = document.createElement('div');
    box.id = 'variantsBox';
    box.className = 'card mt-4';
    box.innerHTML = '<div class="font-semibold mb-2">Variants</div><div id="variantsBody" class="text-sm text-slate-600">Loading…</div>';
    anchor && anchor.appendChild(box);
  }
  return box;
}
function renderVariantsBody(items, source){
  const el = document.getElementById('variantsBody');
  if(!el) return;
  if(!items || !items.length){
    el.innerHTML = '<div class="text-slate-500">No variants (source: '+(source||'?')+')</div>';
    return;
  }
  var rows='';
  items.forEach(it=>{
    const st = (it.status===1?'enabled':(it.status===2?'disabled':String(it.status||'')));
    rows += '<tr><td class="py-2 px-2">'+(it.sku||'')+'</td><td class="py-2 px-2">'+(it.name||'')+'</td><td class="py-2 px-2">'+(typeof it.price==='number'?it.price:'')+'</td><td class="py-2 px-2">'+st+'</td></tr>';
  });
  el.innerHTML = '<div class="mb-2 text-xs text-slate-500">source: '+(source||'?')+'</div>'+
    '<div class="overflow-auto"><table class="min-w-full text-sm"><thead><tr class="text-left text-slate-500"><th class="py-2 px-2">SKU</th><th class="py-2 px-2">Name</th><th class="py-2 px-2">Price</th><th class="py-2 px-2">Status</th></tr></thead><tbody>'+rows+'</tbody></table></div>';
}
async function postRenderVariantsFix(){
  const parts = currentRouteParts();
  if(parts.route !== 'product') return; // kun på produktsiden
  const sku = decodeURIComponent(parts.arg || '').trim() || (function(){
    // fallbacks: forsøk å plukke SKU fra heading/body hvis noen viser den
    const h = document.querySelector('#view h1');
    if(h){ return (h.textContent||'').trim() }
    return '';
  })();

  if(!sku) return;
  ensureVariantsBox();
  renderVariantsBody([], 'loading');

  const j = await fetchVariantsForSku(sku);
  const items = j.items || [];
  renderVariantsBody(items, j.source || 'unknown');
}
// oppdater ved hash-endring (navigering)
addEventListener('hashchange', ()=>{ setTimeout(postRenderVariantsFix, 0) })
</script>
</body>`)
}

fs.writeFileSync(f,s,'utf8')
console.log('Admin UI patched with resilient variants post-render hook.')
NODE

# restart
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
: > "$LOG"
( cd apps/api && nohup npm run start > "../../$LOG" 2>&1 & echo $! > "../../$PIDF" )
sleep 1.6
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "🖥️ Admin UI →"; echo "http://127.0.0.1:$PORT/v2/admin#/product/TEST"
