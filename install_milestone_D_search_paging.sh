#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
UI="$API/src/plugins/admin.ui.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

# Patch admin.ui.js in-place (adds search + pagination to products & orders)
node <<'NODE'
import fs from 'fs';
const file = 'apps/api/src/plugins/admin.ui.js';
let s = fs.readFileSync(file,'utf8');

// -- Replace viewProducts
s = s.replace(/async function viewProducts[\s\S]*?viewProducts;/,
`async function viewProducts(){
  const params=new URLSearchParams(location.hash.split('?')[1]||'');
  const q=params.get('q')||'';
  const page=Number(params.get('page')||1);
  const pageSize=12;
  const r=await fetch('/v2/integrations/magento/products?page='+page+'&pageSize='+pageSize+'&q='+encodeURIComponent(q));
  const j=await r.json();
  const items=j.items||[];
  const total=j.total||j.total_count||items.length;
  const pages=Math.max(1,Math.ceil(total/pageSize));

  let cards='';
  items.forEach(p=>{
    cards+= '<div class="card"><div class="font-semibold mb-1">'+(p.name||'')+'</div>'+
      '<div class="text-sm text-slate-600 mb-2">'+(p.sku||'')+'</div>'+
      '<div class="flex items-center justify-between">'+
        '<span class="text-sm">'+p.price+' NOK · <span class="tag">'+(p.status===1?'Enabled':'Disabled')+'</span></span>'+
        '<a class="btn btn-soft" href="#/product/'+encodeURIComponent(p.sku||'')+'">Open</a></div></div>';
  });

  document.getElementById('view').innerHTML =
    '<div class="mb-4 flex items-center justify-between">'+
      '<h1 class="text-xl font-semibold">Products</h1>'+
      '<form id="searchForm" class="flex gap-2">'+
        '<input id="searchInput" type="text" placeholder="Search…" value="'+q+'" class="border rounded px-2 py-1 text-sm"/>'+
        '<button class="btn btn-primary">Search</button></form>'+
    '</div>'+
    '<div class="grid-auto">'+cards+'</div>'+
    '<div class="mt-4 flex items-center justify-between">'+
      '<button id="prevPage" class="btn btn-soft" '+(page<=1?'disabled':'')+'>Prev</button>'+
      '<div class="text-sm text-slate-600">Page '+page+' of '+pages+' ('+total+' items)</div>'+
      '<button id="nextPage" class="btn btn-soft" '+(page>=pages?'disabled':'')+'>Next</button>'+
    '</div>';

  document.getElementById('searchForm').onsubmit=(e)=>{
    e.preventDefault();
    const term=document.getElementById('searchInput').value;
    location.hash='#/products?q='+encodeURIComponent(term)+'&page=1';
  };
  document.getElementById('prevPage').onclick=()=>{ if(page>1) location.hash='#/products?q='+encodeURIComponent(q)+'&page='+(page-1); };
  document.getElementById('nextPage').onclick=()=>{ if(page<pages) location.hash='#/products?q='+encodeURIComponent(q)+'&page='+(page+1); };
}
viewProducts;`);

// -- Replace viewOrders
s = s.replace(/async function viewOrders[\s\S]*?viewOrders;/,
`async function viewOrders(){
  const params=new URLSearchParams(location.hash.split('?')[1]||'');
  const q=params.get('q')||'';
  const page=Number(params.get('page')||1);
  const pageSize=10;
  const r=await fetch('/v2/integrations/magento/orders?page='+page+'&pageSize='+pageSize+'&q='+encodeURIComponent(q));
  const j=await r.json();
  const list=j.items||[];
  const total=j.total||j.total_count||list.length;
  const pages=Math.max(1,Math.ceil(total/pageSize));

  let rows='';
  list.forEach(o=>{
    rows+= '<tr class="border-b"><td class="py-2 px-2">'+o.entity_id+'</td>'+
      '<td class="py-2 px-2">'+(o.increment_id||'')+'</td>'+
      '<td class="py-2 px-2">'+(o.status||'')+'</td>'+
      '<td class="py-2 px-2">'+o.grand_total+' NOK</td>'+
      '<td class="py-2 px-2 text-right"><a class="btn btn-soft" href="#/order/'+o.entity_id+'">Open</a></td></tr>';
  });

  document.getElementById('view').innerHTML =
    '<div class="mb-4 flex items-center justify-between">'+
      '<h1 class="text-xl font-semibold">Orders</h1>'+
      '<form id="orderSearch" class="flex gap-2">'+
        '<input id="orderInput" type="text" placeholder="Search ID / keyword" value="'+q+'" class="border rounded px-2 py-1 text-sm"/>'+
        '<button class="btn btn-primary">Search</button></form>'+
    '</div>'+
    '<div class="card overflow-auto">'+
      '<table class="min-w-full text-sm"><thead><tr class="text-left text-slate-500">'+
      '<th class="py-2 px-2">ID</th><th class="py-2 px-2">Increment</th><th class="py-2 px-2">Status</th><th class="py-2 px-2">Total</th><th></th>'+
      '</tr></thead><tbody>'+rows+'</tbody></table>'+
    '</div>'+
    '<div class="mt-4 flex items-center justify-between">'+
      '<button id="orderPrev" class="btn btn-soft" '+(page<=1?'disabled':'')+'>Prev</button>'+
      '<div class="text-sm text-slate-600">Page '+page+' of '+pages+' ('+total+' orders)</div>'+
      '<button id="orderNext" class="btn btn-soft" '+(page>=pages?'disabled':'')+'>Next</button>'+
    '</div>';

  document.getElementById('orderSearch').onsubmit=(e)=>{e.preventDefault();
    const term=document.getElementById('orderInput').value;
    location.hash='#/orders?q='+encodeURIComponent(term)+'&page=1';
  };
  document.getElementById('orderPrev').onclick=()=>{if(page>1) location.hash='#/orders?q='+encodeURIComponent(q)+'&page='+(page-1);};
  document.getElementById('orderNext').onclick=()=>{if(page<pages) location.hash='#/orders?q='+encodeURIComponent(q)+'&page='+(page+1);};
}
viewOrders;`);

fs.writeFileSync(file,s,'utf8');
console.log('Patched admin.ui.js with search + paging');
NODE

# restart
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true
echo "🖥️ Admin UI →"; echo "http://127.0.0.1:$PORT/v2/admin"
