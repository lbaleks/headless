#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
UI="$API/src/plugins/admin.ui.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

cat > "$UI" <<'JS'
export default async function adminUi(app) {
  app.get('/v2/admin', async (_req, reply) => {
    const html =
'<!doctype html><html lang="en"><head>'+
'<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>'+
'<title>Litebrygg Admin</title>'+
'<script src="https://cdn.tailwindcss.com"></script>'+
'<style>.card{background:#fff;border-radius:1rem;box-shadow:0 1px 8px rgba(15,23,42,.08);padding:1.25rem}.btn{padding:.5rem .75rem;border-radius:.75rem;box-shadow:0 1px 4px rgba(15,23,42,.08);font-size:.875rem}.btn-primary{background:#4f46e5;color:#fff}.btn-soft{background:#f1f5f9;color:#0f172a}.tag{font-size:.75rem;border-radius:.375rem;padding:.25rem .5rem;background:#f1f5f9}.grid-auto{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:1rem}</style>'+
'</head><body class="bg-slate-50">'+
'<header class="sticky top-0 z-20 bg-slate-900 text-white"><div class="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between">'+
'<div class="font-semibold">Litebrygg Admin</div>'+
'<nav class="flex gap-2"><a href="#/orders" class="tag">Orders</a><a href="#/products" class="tag">Products</a><a href="#/invoices" class="tag">Invoices</a><a href="#/creditmemos" class="tag">Credit Memos</a><a href="#/msi" class="tag">MSI</a><a href="/v2/docs" class="tag">Docs</a></nav>'+
'</div></header>'+
'<main class="max-w-6xl mx-auto px-4 py-6"><div id="notice" class="hidden mb-4"></div><div id="view"></div></main>'+
'<script>(function(){'+
'const api=(p,opt)=>fetch(p,Object.assign({headers:{"content-type":"application/json"}},opt||{}));'+
'function showNotice(text,ok){var n=document.getElementById("notice");n.className= ok? "card mb-4 bg-green-50 text-green-900":"card mb-4 bg-rose-50 text-rose-900";n.textContent=text;n.classList.remove("hidden");setTimeout(function(){n.classList.add("hidden")},4500)};'+
'function fmtMoney(n){try{return new Intl.NumberFormat("no-NO",{style:"currency",currency:"NOK"}).format(Number(n||0))}catch(e){return String(n)}};'+

'async function viewProducts(){const r=await api("/v2/integrations/magento/products?page=1&pageSize=12"); const j=await r.json(); const items=j.items||[]; var cards=""; items.forEach(function(p){cards+= "<div class=\\"card\\"><div class=\\"font-semibold mb-1\\">"+(p.name||"")+"</div><div class=\\"text-sm text-slate-600 mb-2\\">"+(p.sku||"")+"</div><div class=\\"flex items-center justify-between\\"><span class=\\"text-sm\\">"+fmtMoney(p.price)+" · <span class=\\"tag\\">"+(p.status===1?"Enabled":"Disabled")+"</span></span><a class=\\"btn btn-soft\\" href=\\"#/product/"+encodeURIComponent(p.sku||"")+ "\\">Open</a></div></div>";}); document.getElementById("view").innerHTML="<div class=\\"mb-4 flex items-center justify-between\\"><h1 class=\\"text-xl font-semibold\\">Products</h1></div><div class=\\"grid-auto\\">"+cards+"</div>";};'+

'async function viewProduct(sku){const r=await api("/v2/integrations/magento/products/"+encodeURIComponent(sku)); const j=await r.json(); const p=j.item||{}; document.getElementById("view").innerHTML="<div class=\\"flex items-center justify-between mb-4\\"><h1 class=\\"text-xl font-semibold\\">"+(p.name||sku)+"</h1><a class=\\"btn btn-soft\\" href=\\"#/products\\">Back</a></div><div class=\\"card\\"><div class=\\"text-sm text-slate-600 mb-2\\">SKU: "+(p.sku||"")+"</div><div class=\\"mb-2\\">Price: <b>"+fmtMoney(p.price)+"</b></div><div>Status: <span class=\\"tag\\">"+(p.status===1?"Enabled":"Disabled")+"</span></div></div>";};'+

'async function viewOrders(){const r=await api("/v2/integrations/magento/orders?page=1&pageSize=12"); const j=await r.json(); const list=j.items||[]; var rows=""; list.forEach(function(o){rows+= "<tr class=\\"border-b\\"><td class=\\"py-2 px-2\\">"+o.entity_id+"</td><td class=\\"py-2 px-2\\">"+(o.increment_id||"")+"</td><td class=\\"py-2 px-2\\">"+(o.status||"")+"</td><td class=\\"py-2 px-2\\">"+fmtMoney(o.grand_total)+"</td><td class=\\"py-2 px-2 text-right\\"><a class=\\"btn btn-soft\\" href=\\"#/order/"+o.entity_id+"\\">Open</a></td></tr>";}); document.getElementById("view").innerHTML="<div class=\\"mb-4 flex items-center justify-between\\"><h1 class=\\"text-xl font-semibold\\">Orders</h1></div><div class=\\"card overflow-auto\\"><table class=\\"min-w-full text-sm\\"><thead><tr class=\\"text-left text-slate-500\\"><th class=\\"py-2 px-2\\">ID</th><th class=\\"py-2 px-2\\">Increment</th><th class=\\"py-2 px-2\\">Status</th><th class=\\"py-2 px-2\\">Total</th><th></th></tr></thead><tbody>"+rows+"</tbody></table></div>";};'+

'async function viewOrder(id){const r=await api("/v2/integrations/magento/orders/"+id); const j=await r.json(); const o=j.item||{}; var rows=""; (o.items||[]).forEach(function(it){rows+= "<tr class=\\"border-b\\"><td class=\\"py-1 px-2\\">"+it.item_id+"</td><td class=\\"py-1 px-2\\">"+(it.sku||"")+"</td><td class=\\"py-1 px-2\\">"+(it.name||"")+"</td><td class=\\"py-1 px-2\\">"+(it.qty_invoiced||0)+"</td><td class=\\"py-1 px-2\\">"+(it.qty_refunded||0)+"</td><td class=\\"py-1 px-2\\">"+fmtMoney(it.price_incl_tax||it.price)+"</td></tr>";}); document.getElementById("view").innerHTML="<div class=\\"flex items-center justify-between mb-4\\"><h1 class=\\"text-xl font-semibold\\">Order #"+(o.increment_id||id)+"</h1><a class=\\"btn btn-soft\\" href=\\"#/orders\\">Back</a></div><div class=\\"grid md:grid-cols-2 gap-4\\"><div class=\\"card\\"><div class=\\"font-semibold mb-2\\">Summary</div><div class=\\"text-sm mb-1\\">Status: <span class=\\"tag\\">"+(o.status||"")+"</span></div><div class=\\"text-sm mb-1\\">Grand Total: <b>"+fmtMoney(o.grand_total)+"</b></div><div class=\\"text-sm mb-1\\">Total Refunded: <b>"+fmtMoney(o.total_refunded||0)+"</b></div><div class=\\"mt-3 flex gap-2\\"><button id=\\"btn-invoice\\" class=\\"btn btn-primary\\">Create Invoice</button><button id=\\"btn-refund\\" class=\\"btn btn-soft\\">Full Refund</button></div><div class=\\"text-xs text-slate-500 mt-2\\">Krever admin (x-api-key eller x-role: admin)</div></div><div class=\\"card overflow-auto\\"><div class=\\"font-semibold mb-2\\">Items</div><table class=\\"min-w-full text-sm\\"><thead><tr class=\\"text-left text-slate-500\\"><th class=\\"py-1 px-2\\">Item ID</th><th class=\\"py-1 px-2\\">SKU</th><th class=\\"py-1 px-2\\">Name</th><th class=\\"py-1 px-2\\">Inv.</th><th class=\\"py-1 px-2\\">Ref.</th><th class=\\"py-1 px-2\\">Price</th></tr></thead><tbody>"+rows+"</tbody></table></div></div>";'+
'  var inv=document.getElementById("btn-invoice"); if(inv){inv.onclick=async function(){const r=await fetch("/v2/integrations/magento/orders/"+id+"/invoice",{method:"POST",headers:{"content-type":"application/json","x-role":"admin","Idempotency-Key":"ui-inv-"+Date.now()},body:"{\\"capture\\":true}"}); const j=await r.json(); showNotice("Invoice: "+JSON.stringify(j));};}'+
'  var ref=document.getElementById("btn-refund"); if(ref){ref.onclick=async function(){const r=await fetch("/v2/integrations/magento/orders/"+id+"/creditmemo/full",{method:"POST",headers:{"content-type":"application/json","x-role":"admin","Idempotency-Key":"ui-crm-"+Date.now()},body:"{\\"notify\\":false,\\"appendComment\\":false,\\"refund_shipping\\":false}"}); const j=await r.json(); showNotice("Refund: "+JSON.stringify(j), j.ok===true);};}'+
'};'+

'async function viewInvoices(){const r=await api("/v2/integrations/magento/invoices?page=1&pageSize=10"); const j=await r.json(); const list=j.items||[]; var rows=""; list.forEach(function(x){rows+= "<tr class=\\"border-b\\"><td class=\\"py-1 px-2\\">"+x.entity_id+"</td><td class=\\"py-1 px-2\\">"+x.order_id+"</td><td class=\\"py-1 px-2\\">"+fmtMoney(x.grand_total)+"</td><td class=\\"py-1 px-2 text-right\\"><a class=\\"btn btn-soft\\" href=\\"#/invoice/"+x.entity_id+"\\">Open</a></td></tr>";}); document.getElementById("view").innerHTML="<h1 class=\\"text-xl font-semibold mb-3\\">Invoices</h1><div class=\\"card overflow-auto\\"><table class=\\"min-w-full text-sm\\"><thead><tr class=\\"text-left text-slate-500\\"><th class=\\"py-1 px-2\\">ID</th><th class=\\"py-1 px-2\\">Order</th><th class=\\"py-1 px-2\\">Total</th><th></th></tr></thead><tbody>"+rows+"</tbody></table></div>";};'+

'async function viewInvoice(id){const r=await api("/v2/integrations/magento/invoices/"+id); const j=await r.json(); const x=j.invoice||{}; document.getElementById("view").innerHTML="<div class=\\"flex items-center justify-between mb-4\\"><h1 class=\\"text-xl font-semibold\\">Invoice #"+id+"</h1><a class=\\"btn btn-soft\\" href=\\"#/invoices\\">Back</a></div><div class=\\"card\\"><div>Order: "+(x.order_id||"")+"</div><div>Total: <b>"+fmtMoney(x.grand_total)+"</b></div></div>";};'+

'async function viewCreditMemos(){const r=await api("/v2/integrations/magento/creditmemos/4"); const j=await r.json(); const x=j.creditmemo||{}; document.getElementById("view").innerHTML="<h1 class=\\"text-xl font-semibold mb-3\\">Credit Memos</h1><div class=\\"card\\"><div>ID: "+(x.entity_id||"4")+"</div><div>Order: "+(x.order_id||"")+"</div><div>Total: <b>"+fmtMoney(x.grand_total||0)+"</b></div></div>";};'+

'async function viewMSI(){const sku="TEST"; const a=await api("/v2/integrations/magento/msi/source-items/"+sku).then(r=>r.json()); const b=await api("/v2/integrations/magento/msi/salable-qty/"+sku+"?stockId=1").then(r=>r.json()); var rows=""; (a.items||[]).forEach(function(it){rows+= "<tr class=\\"border-b\\"><td class=\\"py-1 px-2\\">"+it.source_code+"</td><td class=\\"py-1 px-2\\">"+(it.status? "In stock":"Out")+"</td><td class=\\"py-1 px-2\\">"+it.quantity+"</td></tr>";}); document.getElementById("view").innerHTML="<div class=\\"flex items-center justify-between mb-4\\"><h1 class=\\"text-xl font-semibold\\">MSI · SKU TEST</h1><div class=\\"tag\\">Salable: "+(b.salable_qty||"–")+" <span class=\\"text-slate-400\\">("+(b.source||"?")+")</span></div></div><div class=\\"card overflow-auto\\"><table class=\\"min-w-full text-sm\\"><thead><tr class=\\"text-left text-slate-500\\"><th class=\\"py-1 px-2\\">Source</th><th class=\\"py-1 px-2\\">Status</th><th class=\\"py-1 px-2\\">Qty</th></tr></thead><tbody>"+rows+"</tbody></table></div>";};'+

'async function router(){var hash=location.hash||"#/orders"; var parts=hash.split("/"); var route=parts[1]||"orders"; var arg=parts[2]; if(route==="products") return viewProducts(); if(route==="product") return viewProduct(decodeURIComponent(arg||"TEST")); if(route==="orders") return viewOrders(); if(route==="order") return viewOrder(arg||"1"); if(route==="invoices") return viewInvoices(); if(route==="invoice") return viewInvoice(arg||"1"); if(route==="creditmemos") return viewCreditMemos(); if(route==="msi") return viewMSI(); return viewOrders();};'+
'addEventListener("hashchange", router); router();'+
'})();</script></body></html>';
    reply.type('text/html').send(html);
  });
}
JS

# restart
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1
echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true
echo "🖥️  Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin"
