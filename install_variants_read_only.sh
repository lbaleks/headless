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

# 1) Variants plugin (read-only)
cat > "$PLUG/variants.js" <<'JS'
import { fetch } from 'undici'
import 'dotenv/config'
const BASE = process.env.M2_BASE_URL || ''
const TOKEN = process.env.M2_ADMIN_TOKEN || ''

async function m2Get(path) {
  const r = await fetch(`${BASE}${path}`, { headers: { Authorization: `Bearer ${TOKEN}` } })
  const t = await r.text()
  let j; try { j = JSON.parse(t) } catch { j = { raw:t } }
  if (!r.ok) throw Object.assign(new Error(`Upstream ${r.status}`), { status:r.status, data:j })
  return j
}

export default async function variants(app) {
  // feature flag legger vi her for enkelhets skyld (kombinerer med eksisterende flags i UI)
  app.addHook('onReady', async function(){
    app.__flags = app.__flags || {}
    app.__flags.m2_variants = true
  })

  // GET children for configurable
  app.get('/v2/integrations/magento/products/:sku/variants', async (req, reply) => {
    const { sku } = req.params
    try {
      // Primær: configurable children
      const children = await m2Get(`/rest/V1/configurable-products/${encodeURIComponent(sku)}/children`)
      if (Array.isArray(children) && children.length) {
        const items = children.map(c => ({
          id: c.id, sku: c.sku, name: c.name, price: c.price, status: c.status, type: c.type_id
        }))
        return { ok:true, source:'configurable-children', items }
      }
      // Fallback: les hovedprodukt og sjekk product_links
      const prod = await m2Get(`/rest/V1/products/${encodeURIComponent(sku)}`)
      const links = prod.product_links || []
      const simples = links.filter(l => l.link_type === 'associated')
      if (simples.length) {
        // Hent hver (kan optimaliseres siden M2 ikke har bulk-by-sku standard her)
        const items = []
        for (const l of simples.slice(0,25)) {
          try {
            const c = await m2Get(`/rest/V1/products/${encodeURIComponent(l.linked_product_sku)}`)
            items.push({ id:c.id, sku:c.sku, name:c.name, price:c.price, status:c.status, type:c.type_id })
          } catch {}
        }
        return { ok:true, source:'product_links', items }
      }
      return { ok:true, source:'none', items:[] }
    } catch (e) {
      reply.code(502); return { ok:false, note:'upstream_failed', error:e.data||String(e) }
    }
  })
}
JS

# 2) Patch server.js – registrer plugin + flagg-eksponering
node <<'NODE'
import fs from 'fs'
const p='apps/api/src/server.js'
let s=fs.readFileSync(p,'utf8')

// tryPlugin finnes alt i din fil – vi gjenbruker mønsteret. Hvis ikke, fallback til app.register.
function ensureTryPluginBlock(txt){
  if(txt.includes('async function tryPlugin(')) return txt
  return txt.replace(
    /const app = Fastify\([^\)]*\)\)\n/s,
`const app = Fastify({ logger: true })

// light-weight plugin loader (non-fatal)
async function tryPlugin(name, path){
  try { const mod = (await import(path)).default; await app.register(mod); app.log.info({ plugin:name }, 'registered') }
  catch (err) { app.log.warn({ plugin:name, err: String(err) }, 'plugin load failed (continuing)') }
}
`
  )
}
s = ensureTryPluginBlock(s)

// legg variants før admin-ui for sikker router
if(!s.includes(`tryPlugin('variants'`)){
  s = s.replace(`await tryPlugin('admin-ui'`, `await tryPlugin('variants', './plugins/variants.js')\nawait tryPlugin('admin-ui'`)
}

// feature-flags endepunkt: speil __flags hvis finnes
if(!s.includes('/v2/feature-flags')){
  // bør allerede finnes – hopper
} else {
  // patch handler til å merge inn __flags
  s = s.replace(/app\.get\('\/v2\/feature-flags',[\s\S]*?\}\)\n\}/, (m)=>{
    if(m.includes('app.__flags')) return m
    return m.replace('return ({', `const merged = Object.assign({ m2_products:true, m2_mutations:true }, app.__flags||{});\n  return ({`)
            .replace(/flags:\s*\{[\s\S]*?\}/, 'flags: merged')
  })
}

fs.writeFileSync(p,s,'utf8')
console.log('Server patched for variants.')
NODE

# 3) Admin UI – legg til "Variants" på produktsiden
node <<'NODE'
import fs from 'fs'
const f='apps/api/src/plugins/admin.ui.js'
let s=fs.readFileSync(f,'utf8')

// Sett inn seksjon på product-visning
if(!s.includes('function renderVariants(')){
  s = s.replace(/function renderProduct\([\s\S]*?\}\n\}\n/, (m)=>{
    // Behold eksisterende renderProduct, men vi injiserer et kall til renderVariants container
    let out = m
    if(!out.includes('id="variantsBox"')) {
      out = out.replace(/(<div id="productMeta">[\s\S]*?<\/div>)/,
        `$1
<div id="variantsBox" class="card mt-4">
  <div class="font-semibold mb-2">Variants</div>
  <div id="variantsBody" class="text-sm text-slate-600">Loading…</div>
</div>`)
    }
    return out
  })

  // hent og tegn varianter når renderProduct er ferdig
  s = s.replace(/(function renderProduct\([^\)]*\)\{[\s\S]*?document\.getElementById\('view'\)\.innerHTML = [\s\S]*?;\n)/,
    `$1
  // spark i gang variant-henting
  try { loadVariants(x.item && x.item.sku || sku) } catch(e){}
`)

  // nye helpers
  s += `
async function loadVariants(sku){
  try{
    const r = await fetch('/v2/integrations/magento/products/'+encodeURIComponent(sku)+'/variants');
    const j = await r.json();
    renderVariants(j.items||[], j.source||'?')
  }catch(e){
    renderVariants([], 'error')
  }
}
function renderVariants(items, source){
  const el = document.getElementById('variantsBody');
  if(!el) return;
  if(!items.length){
    el.innerHTML = '<div class="text-slate-500">No variants (source: '+source+')</div>';
    return;
  }
  var rows = '';
  items.forEach(it=>{
    const st = (it.status===1?'enabled':(it.status===2?'disabled':String(it.status)));
    rows += '<tr><td class="py-2 px-2">'+(it.sku||'')+'</td><td class="py-2 px-2">'+(it.name||'')+'</td><td class="py-2 px-2">'+(typeof it.price==='number'?(''+it.price):'')+'</td><td class="py-2 px-2">'+st+'</td></tr>';
  })
  el.innerHTML =
    '<div class="mb-2 text-xs text-slate-500">source: '+source+'</div>'+
    '<div class="overflow-auto"><table class="min-w-full text-sm"><thead><tr class="text-left text-slate-500"><th class="py-2 px-2">SKU</th><th class="py-2 px-2">Name</th><th class="py-2 px-2">Price</th><th class="py-2 px-2">Status</th></tr></thead><tbody>'+rows+'</tbody></table></div>';
}
`
}

fs.writeFileSync(f,s,'utf8')
console.log('Admin UI patched with Variants section.')
NODE

# 4) Restart & smoke
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then lsof -ti tcp:"$PORT" | xargs -r kill -9 || true; fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 2
echo "�� Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "⚙️ Flags:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/feature-flags" || true; echo
echo "🔎 Variants (TEST):"; curl -sS --max-time 10 "http://127.0.0.1:$PORT/v2/integrations/magento/products/TEST/variants" || true; echo
echo "🖥️ Admin UI:"; echo "http://127.0.0.1:$PORT/v2/admin#/product/TEST"
