#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
UI="$API/src/plugins/admin.ui.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

mkdir -p "$API/src/plugins"

# Skriv en helt ren, syntaktisk trygg admin.ui.js
cat > "$UI" <<'JS'
export default async function adminUi(app) {
  app.get('/v2/admin', async (_req, reply) => {
    const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Litebrygg Admin</title>
<script src="https://cdn.tailwindcss.com"></script>
<style>
.card{background:#fff;border-radius:1rem;box-shadow:0 1px 8px rgba(15,23,42,.08);padding:1.25rem}
.btn{padding:.5rem .75rem;border-radius:.75rem;box-shadow:0 1px 4px rgba(15,23,42,.08);font-size:.875rem}
.btn-primary{background:#4f46e5;color:#fff}
.btn-soft{background:#f1f5f9;color:#0f172a}
.tag{font-size:.75rem;border-radius:.375rem;padding:.25rem .5rem;background:#f1f5f9}
.grid-auto{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:1rem}
.input{border:1px solid #cbd5e1;border-radius:.5rem;padding:.375rem .5rem;font-size:.875rem}
.table{width:100%;border-collapse:collapse}
th,td{padding:.5rem .5rem;text-align:left}
thead th{color:#64748b}
tr{border-bottom:1px solid #e2e8f0}
</style>
</head>
<body class="bg-slate-50">
<header class="sticky top-0 z-20 bg-slate-900 text-white">
  <div class="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between">
    <div class="font-semibold">Litebrygg Admin</div>
    <nav class="flex gap-2">
      <a href="#/orders" class="tag">Orders</a>
      <a href="#/products" class="tag">Products</a>
      <a href="/v2/docs" class="tag">Docs</a>
    </nav>
  </div>
</header>
<main class="max-w-6xl mx-auto px-4 py-6">
  <div id="notice" class="hidden mb-4"></div>
  <div id="view"></div>
</main>

<script>
(function(){
  const api = (p,opt)=>fetch(p,Object.assign({headers:{"content-type":"application/json"}},opt||{}));
  function showNotice(text,ok){
    var n=document.getElementById('notice');
    n.className = ok? 'card mb-4 bg-green-50 text-green-900' : 'card mb-4 bg-rose-50 text-rose-900';
    n.textContent = text; n.classList.remove('hidden'); setTimeout(()=>n.classList.add('hidden'), 4000);
  }
  function fmt(n){ try{ return new Intl.NumberFormat('no-NO',{style:'currency',currency:'NOK'}).format(Number(n||0)) } catch(e){ return String(n) } }
  function getParams(){ var q=(location.hash.split('?')[1]||''); return new URLSearchParams(q) }
  function setHash(route, params){ var s=new URLSearchParams(params).toString(); location.hash = route + (s? '?' + s : '') }

  async function viewProducts(){
    var params=getParams(); var q=params.get('q')||''; var page=Number(params.get('page')||1); var pageSize=12;
    const r = await api('/v2/integrations/magento/products?page='+page+'&pageSize='+pageSize+'&q='+encodeURIComponent(q));
    const j = await r.json(); const items=j.items||[];
    const total = j.total || j.total_count || items.length; const pages = Math.max(1, Math.ceil(total/pageSize));
    var cards = '';
    items.forEach(function(p){
      cards += '<div class="card">'+
        '<div class="font-semibold mb-1">'+(p.name||'')+'</div>'+
        '<div class="text-sm text-slate-600 mb-2">'+(p.sku||'')+'</div>'+
        '<div class="flex items-center justify-between">'+
          '<span class="text-sm">'+fmt(p.price)+' · <span class="tag">'+(p.status===1?'Enabled':'Disabled')+'</span></span>'+
          '<a class="btn btn-soft" href="#/product/'+encodeURIComponent(p.sku||'')+'">Open</a>'+
        '</div>'+
      '</div>';
    });
    document.getElementById('view').innerHTML =
      '<div class="mb-4 flex items-center justify-between">'+
        '<h1 class="text-xl font-semibold">Products</h1>'+
        '<form id="searchForm" class="flex gap-2">'+
          '<input id="searchInput" class="input" type="text" placeholder="Search…" value="'+q.replace(/"/g,'&quot;')+'"/>'+
          '<button class="btn btn-primary">Search</button>'+
        '</form>'+
      '</div>'+
      '<div class="grid-auto">'+cards+'</div>'+
      '<div class="mt-4 flex items-center justify-between">'+
        '<button id="prevPage" class="btn btn-soft" '+(page<=1?'disabled':'')+'>Prev</button>'+
        '<div class="text-sm text-slate-600">Page '+page+' of '+pages+' ('+total+' items)</div>'+
        '<button id="nextPage" class="btn btn-soft" '+(page>=pages?'disabled':'')+'>Next</button>'+
      '</div>';

    document.getElementById('searchForm').onsubmit=function(e){ e.preventDefault(); var term=document.getElementById('searchInput').value; setHash('#/products',{q:term,page:1}) };
    var pv=document.getElementById('prevPage'); if(pv) pv.onclick=function(){ if(page>1) setHash('#/products',{q:q,page:page-1}) };
    var nx=document.getElementById('nextPage'); if(nx) nx.onclick=function(){ if(page<pages) setHash('#/products',{q:q,page:page+1}) };
  }

  async function viewProduct(sku){
    const r = await api('/v2/integrations/magento/products/'+encodeURIComponent(sku));
    const j = await r.json(); const p=j.item||{};
    document.getElementById('view').innerHTML =
      '<div class="flex items-center justify-between mb-4">'+
        '<h1 class="text-xl font-semibold">'+(p.name||sku)+'</h1>'+
        '<a class="btn btn-soft" href="#/products">Back</a>'+
      '</div>'+
      '<div class="card">'+
        '<div class="text-sm text-slate-600 mb-2">SKU: '+(p.sku||'')+'</div>'+
        '<div class="mb-2">Price: <b>'+fmt(p.price)+'</b></div>'+
        '<div>Status: <span class="tag">'+(p.status===1?'Enabled':'Disabled')+'</span></div>'+
      '</div>';
  }

  async function viewOrders(){
    var params=getParams(); var q=params.get('q')||''; var page=Number(params.get('page')||1); var pageSize=10;
    const r = await api('/v2/integrations/magento/orders?page='+page+'&pageSize='+pageSize+'&q='+encodeURIComponent(q));
    const j = await r.json(); const list=j.items||[];
    const total = j.total || j.total_count || list.length; const pages = Math.max(1, Math.ceil(total/pageSize));
    var rows='';
    list.forEach(function(o){
      rows+='<tr><td>'+o.entity_id+'</td><td>'+(o.increment_id||'')+'</td><td>'+(o.status||'')+'</td><td>'+fmt(o.grand_total)+'</td>'+
            '<td class="text-right"><a class="btn btn-soft" href="#/order/'+o.entity_id+'">Open</a></td></tr>';
    });
    document.getElementById('view').innerHTML =
      '<div class="mb-4 flex items-center justify-between">'+
        '<h1 class="text-xl font-semibold">Orders</h1>'+
        '<form id="orderSearch" class="flex gap-2">'+
          '<input id="orderInput" class="input" type="text" placeholder="Search ID / keyword" value="'+q.replace(/"/g,'&quot;')+'"/>'+
          '<button class="btn btn-primary">Search</button>'+
        '</form>'+
      '</div>'+
      '<div class="card overflow-auto">'+
        '<table class="table text-sm"><thead><tr>'+
          '<th>ID</th><th>Increment</th><th>Status</th><th>Total</th><th></th>'+
        '</tr></thead><tbody>'+rows+'</tbody></table>'+
      '</div>'+
      '<div class="mt-4 flex items-center justify-between">'+
        '<button id="orderPrev" class="btn btn-soft" '+(page<=1?'disabled':'')+'>Prev</button>'+
        '<div class="text-sm text-slate-600">Page '+page+' of '+pages+' ('+total+' orders)</div>'+
        '<button id="orderNext" class="btn btn-soft" '+(page>=pages?'disabled':'')+'>Next</button>'+
      '</div>';
    document.getElementById('orderSearch').onsubmit=function(e){e.preventDefault(); var term=document.getElementById('orderInput').value; setHash('#/orders',{q:term,page:1})};
    var pv=document.getElementById('orderPrev'); if(pv) pv.onclick=function(){ if(page>1) setHash('#/orders',{q:q,page:page-1}) };
    var nx=document.getElementById('orderNext'); if(nx) nx.onclick=function(){ if(page<pages) setHash('#/orders',{q:q,page:page+1}) };
  }

  async function viewOrder(id){
    const r=await api('/v2/integrations/magento/orders/'+id); const j=await r.json(); const o=j.item||{};
    var rows='';
    (o.items||[]).forEach(function(it){
      rows+='<tr><td>'+it.item_id+'</td><td>'+(it.sku||'')+'</td><td>'+(it.name||'')+'</td><td>'+(it.qty_invoiced||0)+'</td><td>'+(it.qty_refunded||0)+'</td><td>'+fmt(it.price_incl_tax||it.price)+'</td></tr>';
    });
    document.getElementById('view').innerHTML =
      '<div class="flex items-center justify-between mb-4"><h1 class="text-xl font-semibold">Order #'+(o.increment_id||id)+'</h1><a class="btn btn-soft" href="#/orders">Back</a></div>'+
      '<div class="grid md:grid-cols-2 gap-4">'+
        '<div class="card">'+
          '<div class="font-semibold mb-2">Summary</div>'+
          '<div class="text-sm mb-1">Status: <span class="tag">'+(o.status||'')+'</span></div>'+
          '<div class="text-sm mb-1">Grand Total: <b>'+fmt(o.grand_total)+'</b></div>'+
          '<div class="text-sm mb-1">Total Refunded: <b>'+fmt(o.total_refunded||0)+'</b></div>'+
        '</div>'+
        '<div class="card overflow-auto">'+
          '<div class="font-semibold mb-2">Items</div>'+
          '<table class="table text-sm"><thead><tr><th>Item ID</th><th>SKU</th><th>Name</th><th>Inv.</th><th>Ref.</th><th>Price</th></tr></thead><tbody>'+rows+'</tbody></table>'+
        '</div>'+
      '</div>';
  }

  async function router(){
    var hash=location.hash||'#/orders'; var parts=hash.split('/'); var route=parts[1]||'orders'; var arg=parts[2];
    if(route==='products') return viewProducts();
    if(route==='product') return viewProduct(decodeURIComponent(arg||'TEST'));
    if(route==='orders') return viewOrders();
    if(route==='order') return viewOrder(arg||'1');
    return viewOrders();
  }
  addEventListener('hashchange', router); router();
})();
</script>
</body>
</html>`;
    reply.type('text/html').send(html);
  });
}
JS

# Restart
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 2

echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true
echo
echo "🔎 HEAD /v2/admin (skal være 200):"; curl -sI --max-time 6 "http://127.0.0.1:$PORT/v2/admin" || true
echo
echo "🪵 Tail log:"; tail -n 50 "$LOG" || true
