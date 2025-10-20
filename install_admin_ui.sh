#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

mkdir -p "$API/src/plugins"

# ────────────────────────────────────────────────────────────────────────────────
# Admin UI plugin (serverer /v2/admin)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API/src/plugins/admin.ui.js" <<'JS'
export default async function adminUi(app) {
  app.get('/v2/admin', async (req, reply) => {
    const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Litebrygg Admin</title>
<script src="https://cdn.tailwindcss.com"></script>
<style>
  .card{ @apply bg-white rounded-2xl shadow p-5; }
  .btn{ @apply px-3 py-2 rounded-xl shadow text-sm; }
  .btn-primary{ @apply bg-indigo-600 text-white; }
  .btn-soft{ @apply bg-slate-100 text-slate-900; }
  .tag{ @apply text-xs rounded px-2 py-1 bg-slate-100; }
  .grid-auto{ grid-template-columns: repeat(auto-fill, minmax(280px,1fr)); }
</style>
</head>
<body class="bg-slate-50">
  <header class="sticky top-0 z-20 bg-slate-900 text-white">
    <div class="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between">
      <div class="font-semibold">Litebrygg Admin</div>
      <nav class="flex gap-2">
        <a href="#/orders" class="tag">Orders</a>
        <a href="#/products" class="tag">Products</a>
        <a href="#/invoices" class="tag">Invoices</a>
        <a href="#/creditmemos" class="tag">Credit Memos</a>
        <a href="#/msi" class="tag">MSI</a>
        <a href="/v2/docs" class="tag">Docs</a>
      </nav>
    </div>
  </header>

  <main class="max-w-6xl mx-auto px-4 py-6">
    <div id="notice" class="hidden mb-4"></div>
    <div id="view"></div>
  </main>

<script>
const api = (p, opt={}) => fetch(p, { ...opt, headers: { 'content-type':'application/json', ...(opt.headers||{}) } });

function showNotice(text, ok=true){
  const n = document.getElementById('notice');
  n.className = ok ? 'card mb-4 bg-green-50 text-green-900' : 'card mb-4 bg-rose-50 text-rose-900';
  n.textContent = text;
  n.classList.remove('hidden');
  setTimeout(()=>n.classList.add('hidden'), 4500);
}

function fmtMoney(n){ try{ return new Intl.NumberFormat('no-NO',{style:'currency',currency:'NOK'}).format(Number(n||0)); }catch(e){ return String(n); } }

async function viewProducts(){
  const r = await api('/v2/integrations/magento/products?page=1&pageSize=12'); const j = await r.json();
  const items = (j.items||[]);
  const cards = items.map(p => `
    <div class="card">
      <div class="font-semibold mb-1">${p.name}</div>
      <div class="text-sm text-slate-600 mb-2">${p.sku}</div>
      <div class="flex items-center justify-between">
        <span class="text-sm">${fmtMoney(p.price)} · <span class="tag">${p.status===1?'Enabled':'Disabled'}</span></span>
        <a class="btn btn-soft" href="#/product/${encodeURIComponent(p.sku)}">Open</a>
      </div>
    </div>
  `).join('');
  document.getElementById('view').innerHTML = `
    <div class="mb-4 flex items-center justify-between">
      <h1 class="text-xl font-semibold">Products</h1>
    </div>
    <div class="grid gap-4 grid-auto">${cards}</div>
  `;
}

async function viewProduct(sku){
  const r = await api('/v2/integrations/magento/products/'+encodeURIComponent(sku)); const j = await r.json();
  const p = j.item||{};
  document.getElementById('view').innerHTML = `
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-semibold">${p.name||sku}</h1>
      <a class="btn btn-soft" href="#/products">Back</a>
    </div>
    <div class="card">
      <div class="text-sm text-slate-600 mb-2">SKU: ${p.sku}</div>
      <div class="mb-2">Price: <b>${fmtMoney(p.price)}</b></div>
      <div>Status: <span class="tag">${p.status===1?'Enabled':'Disabled'}</span></div>
    </div>
  `;
}

async function viewOrders(){
  const r = await api('/v2/integrations/magento/orders?page=1&pageSize=12'); const j = await r.json();
  const rows = (j.items||[]).map(o => `
    <tr class="border-b">
      <td class="py-2 px-2">${o.entity_id}</td>
      <td class="py-2 px-2">${o.increment_id||''}</td>
      <td class="py-2 px-2">${o.status}</td>
      <td class="py-2 px-2">${fmtMoney(o.grand_total)}</td>
      <td class="py-2 px-2 text-right"><a class="btn btn-soft" href="#/order/${o.entity_id}">Open</a></td>
    </tr>
  `).join('');
  document.getElementById('view').innerHTML = `
    <div class="mb-4 flex items-center justify-between">
      <h1 class="text-xl font-semibold">Orders</h1>
    </div>
    <div class="card overflow-auto">
      <table class="min-w-full text-sm">
        <thead><tr class="text-left text-slate-500">
          <th class="py-2 px-2">ID</th><th class="py-2 px-2">Increment</th><th class="py-2 px-2">Status</th><th class="py-2 px-2">Total</th><th></th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

async function viewOrder(id){
  const r = await api('/v2/integrations/magento/orders/'+id); const j = await r.json();
  const o = j.item||{};
  const items = (o.items||[]).map(it => `
    <tr class="border-b">
      <td class="py-1 px-2">${it.item_id}</td>
      <td class="py-1 px-2">${it.sku}</td>
      <td class="py-1 px-2">${it.name}</td>
      <td class="py-1 px-2">${it.qty_invoiced||0}</td>
      <td class="py-1 px-2">${it.qty_refunded||0}</td>
      <td class="py-1 px-2">${fmtMoney(it.price_incl_tax||it.price)}</td>
    </tr>`).join('');
  document.getElementById('view').innerHTML = `
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-semibold">Order #${o.increment_id||id}</h1>
      <a class="btn btn-soft" href="#/orders">Back</a>
    </div>
    <div class="grid md:grid-cols-2 gap-4">
      <div class="card">
        <div class="font-semibold mb-2">Summary</div>
        <div class="text-sm mb-1">Status: <span class="tag">${o.status}</span></div>
        <div class="text-sm mb-1">Grand Total: <b>${fmtMoney(o.grand_total)}</b></div>
        <div class="text-sm mb-1">Total Refunded: <b>${fmtMoney(o.total_refunded||0)}</b></div>
        <div class="mt-3 flex gap-2">
          <button id="btn-invoice" class="btn btn-primary">Create Invoice</button>
          <button id="btn-refund" class="btn btn-soft">Full Refund</button>
        </div>
        <div class="text-xs text-slate-500 mt-2">Krever admin (x-api-key eller x-role: admin)</div>
      </div>
      <div class="card overflow-auto">
        <div class="font-semibold mb-2">Items</div>
        <table class="min-w-full text-sm">
          <thead><tr class="text-left text-slate-500">
            <th class="py-1 px-2">Item ID</th><th class="py-1 px-2">SKU</th><th class="py-1 px-2">Name</th><th class="py-1 px-2">Inv.</th><th class="py-1 px-2">Ref.</th><th class="py-1 px-2">Price</th>
          </tr></thead>
          <tbody>${items}</tbody>
        </table>
      </div>
    </div>
    <script>
      document.getElementById('btn-invoice').onclick = async () => {
        const r = await fetch('/v2/integrations/magento/orders/${id}/invoice', { method:'POST', headers: { 'content-type':'application/json', 'x-role':'admin', 'Idempotency-Key':'ui-inv-'+Date.now() }, body: JSON.stringify({ capture: true }) });
        const j = await r.json(); showNotice('Invoice: '+JSON.stringify(j));
      }
      document.getElementById('btn-refund').onclick = async () => {
        const r = await fetch('/v2/integrations/magento/orders/${id}/creditmemo/full', { method:'POST', headers: { 'content-type':'application/json', 'x-role':'admin', 'Idempotency-Key':'ui-crm-'+Date.now() }, body: JSON.stringify({ notify:false, appendComment:false, refund_shipping:false }) });
        const j = await r.json(); showNotice('Refund: '+JSON.stringify(j), j.ok===true);
      }
    </script>
  `;
}

async function viewInvoices(){
  const r = await api('/v2/integrations/magento/invoices?page=1&pageSize=10'); const j = await r.json();
  const rows = (j.items||[]).map(x => `
    <tr class="border-b">
      <td class="py-1 px-2">${x.entity_id}</td>
      <td class="py-1 px-2">${x.order_id}</td>
      <td class="py-1 px-2">${fmtMoney(x.grand_total)}</td>
      <td class="py-1 px-2 text-right"><a class="btn btn-soft" href="#/invoice/${x.entity_id}">Open</a></td>
    </tr>`).join('');
  document.getElementById('view').innerHTML = `
    <h1 class="text-xl font-semibold mb-3">Invoices</h1>
    <div class="card overflow-auto">
      <table class="min-w-full text-sm">
        <thead><tr class="text-left text-slate-500">
          <th class="py-1 px-2">ID</th><th class="py-1 px-2">Order</th><th class="py-1 px-2">Total</th><th></th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}
async function viewInvoice(id){
  const r = await api('/v2/integrations/magento/invoices/'+id); const j = await r.json(); const x = j.invoice||{};
  document.getElementById('view').innerHTML = `
    <div class="flex items-center justify-between mb-4"><h1 class="text-xl font-semibold">Invoice #${id}</h1><a class="btn btn-soft" href="#/invoices">Back</a></div>
    <div class="card"><div>Order: ${x.order_id}</div><div>Total: <b>${fmtMoney(x.grand_total)}</b></div></div>`;
}

async function viewCreditMemos(){
  // best-effort list via order 1 som demo
  const r = await api('/v2/integrations/magento/creditmemos/4'); const j = await r.json(); const x = j.creditmemo||{};
  document.getElementById('view').innerHTML = `
    <h1 class="text-xl font-semibold mb-3">Credit Memos</h1>
    <div class="card"><div>ID: ${x.entity_id||'4'}</div><div>Order: ${x.order_id||''}</div><div>Total: <b>${fmtMoney(x.grand_total||0)}</b></div></div>`;
}

async function viewMSI(){
  const sku = 'TEST';
  const [a,b] = await Promise.all([
    api('/v2/integrations/magento/msi/source-items/'+sku).then(r=>r.json()),
    api('/v2/integrations/magento/msi/salable-qty/'+sku+'?stockId=1').then(r=>r.json())
  ]);
  const rows = (a.items||[]).map(it=>`
    <tr class="border-b">
      <td class="py-1 px-2">${it.source_code}</td>
      <td class="py-1 px-2">${it.status? 'In stock':'Out'}</td>
      <td class="py-1 px-2">${it.quantity}</td>
    </tr>`).join('');
  document.getElementById('view').innerHTML = `
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-semibold">MSI · SKU TEST</h1>
      <div class="tag">Salable: ${(b.salable_qty??'–')} <span class="text-slate-400">(${b.source})</span></div>
    </div>
    <div class="card overflow-auto">
      <table class="min-w-full text-sm">
        <thead><tr class="text-left text-slate-500"><th class="py-1 px-2">Source</th><th class="py-1 px-2">Status</th><th class="py-1 px-2">Qty</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

async function router(){
  const hash = location.hash || '#/orders';
  const [_, route, arg] = hash.split('/');
  if (route==='products') return viewProducts();
  if (route==='product')  return viewProduct(decodeURIComponent(arg||'TEST'));
  if (route==='orders')   return viewOrders();
  if (route==='order')    return viewOrder(arg||'1');
  if (route==='invoices') return viewInvoices();
  if (route==='invoice')  return viewInvoice(arg||'1');
  if (route==='creditmemos') return viewCreditMemos();
  if (route==='msi') return viewMSI();
  return viewOrders();
}
addEventListener('hashchange', router);
router();
</script>
</body>
</html>`;
    reply.type('text/html').send(html);
  });
}
JS

# Patch server.js: importer og registrer admin-ui (Node, idempotent)
node <<'NODE'
const fs = require('fs');
const p = 'apps/api/src/server.js';
let s = fs.readFileSync(p, 'utf8');
function ensureImport(code, sym, file){ if(!code.includes(`import ${sym} from '${file}'`)){ code = `import ${sym} from '${file}'\n` + code; } return code; }
function insertAfter(code, anchor, insert){ const i = code.indexOf(anchor); if(i===-1) return code + '\n' + insert; const j=i+anchor.length; return code.slice(0,j)+'\n'+insert+code.slice(j); }
s = ensureImport(s, 'adminUi', './plugins/admin.ui.js');
if (!s.includes('register(adminUi)')) {
  // legg admin UI helt sist før listen
  s = insertAfter(s, 'await app.register(openapi)', 'await app.register(adminUi)');
}
fs.writeFileSync(p, s, 'utf8'); console.log('Patched server.js with admin-ui');
NODE

# Restart
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1

echo "🩺 Health:";  curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true
echo "🖥️  Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin"
