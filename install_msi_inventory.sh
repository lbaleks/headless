#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

mkdir -p "$API/src/plugins"

# ────────────────────────────────────────────────────────────────────────────────
# MSI plugin
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API/src/plugins/magento2.msi.js" <<'JS'
import { ensureEnv, m2Get, m2Post } from './_m2util.js'

/**
 * Magento MSI REST (typisk):
 *  - GET  /rest/V1/inventory/source-items?searchCriteria[...]=...
 *  - POST /rest/V1/inventory/source-items   { "sourceItems":[ {sku,source_code,quantity,status} ] }
 *  - GET  /rest/V1/inventory/get-product-salable-qty/{sku}/{stockId}
 *
 * status: 1=in stock, 0=out of stock
 */
export default async function msi(app) {
  // Admin gate for mutasjoner
  app.addHook('onRequest', async (req, reply) => {
    if (req.method !== 'GET' && req.url.startsWith('/v2/integrations/magento/msi/')) {
      const role = req.headers['x-role'] || (req.user && req.user.role)
      if (role !== 'admin') {
        reply.code(403)
        return reply.send({ ok:false, code:'forbidden', title:'Admin role required' })
      }
    }
  })

  // List source-items for SKU
  app.get('/v2/integrations/magento/msi/source-items/:sku', async (req) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { sku } = req.params
    const params = new URLSearchParams()
    // search: field=sku eq
    params.set('searchCriteria[filter_groups][0][filters][0][field]', 'sku')
    params.set('searchCriteria[filter_groups][0][filters][0][value]', String(sku))
    params.set('searchCriteria[filter_groups][0][filters][0][condition_type]', 'eq')
    try {
      const data = await m2Get(`/rest/V1/inventory/source-items?${params.toString()}`)
      return { ok:true, items: data.items || data || [] }
    } catch (e) {
      return { ok:false, note:'upstream_failed', error:e.data }
    }
  })

  // Update single source-item (wrapped into API bulk contract)
  app.put('/v2/integrations/magento/msi/source-items', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return reply.code(400).send({ ok:false, note:'env_missing', missing:miss })
    const { sku, source_code, qty, status } = req.body || {}
    if (!sku || !source_code || typeof qty !== 'number' || ![0,1,true,false].includes(status)) {
      reply.code(400)
      return { ok:false, code:'bad_request', title:'Required: sku:string, source_code:string, qty:number, status:(0|1|true|false)' }
    }
    const st = status === true ? 1 : status === false ? 0 : status
    const idem = req.headers['idempotency-key']
    try {
      const payload = { sourceItems: [{ sku, source_code, quantity: qty, status: st }] }
      const res = await m2Post('/rest/V1/inventory/source-items', payload, idem ? { 'Idempotency-Key': idem } : undefined)
      return { ok:true, updated: { sku, source_code, qty, status: st }, upstream: res || { saved: true } }
    } catch (e) {
      reply.code(502); return { ok:false, code:'upstream_failed', detail:e.data }
    }
  })

  // Salable qty (stockId=1 by default)
  app.get('/v2/integrations/magento/msi/salable-qty/:sku', async (req) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { sku } = req.params
    const stockId = Number(req.query.stockId ?? 1)
    try {
      const qty = await m2Get(`/rest/V1/inventory/get-product-salable-qty/${encodeURIComponent(sku)}/${encodeURIComponent(stockId)}`)
      return { ok:true, sku, stockId, salable_qty: typeof qty === 'number' ? qty : Number(qty) }
    } catch (e) {
      return { ok:false, note:'upstream_failed', error:e.data }
    }
  })
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# Feature flags superset (legg på m2_msi)
# ────────────────────────────────────────────────────────────────────────────────
FF="$API/src/plugins/feature-flags.js"
if [ -f "$FF" ]; then
  if ! grep -q "m2_msi" "$FF"; then
    # enkel overwrite for å være sikker på konsistens
    cat > "$FF" <<'JS'
export default async function featureFlagsPlugin (app) {
  app.get('/v2/feature-flags', async () => ({
    ok: true,
    flags: {
      m2_products: true,
      m2_mutations: true,
      m2_customers: true,
      m2_orders: true,
      m2_categories: true,
      m2_sales_rules: true,
      m2_creditmemos: true,
      m2_invoices: true,
      rbac: true,
      openapi: true,
      m2_msi: true
    }
  }))
}
JS
  fi
fi

# ────────────────────────────────────────────────────────────────────────────────
# Patch server.js – import og register MSI plugin (Node-patcher, idempotent)
# ────────────────────────────────────────────────────────────────────────────────
node <<'NODE'
const fs = require('fs');
const path = 'apps/api/src/server.js';
let s = fs.readFileSync(path, 'utf8');

function ensureImport(code, sym, file) {
  if (!code.includes(`import ${sym} from '${file}'`)) {
    code = `import ${sym} from '${file}'\n` + code;
  }
  return code;
}
function insertAfter(code, anchor, insert) {
  const i = code.indexOf(anchor);
  if (i === -1) return code + '\n' + insert; // fallback append
  const j = i + anchor.length;
  return code.slice(0, j) + '\n' + insert + code.slice(j);
}

s = ensureImport(s, 'm2MSI', './plugins/magento2.msi.js');

if (!s.includes('register(m2MSI)')) {
  // Registrer MSI etter sales rules eller etter orders hvis ikke finnes
  if (s.includes('await app.register(m2SalesRules)')) {
    s = insertAfter(s, 'await app.register(m2SalesRules)', 'await app.register(m2MSI)');
  } else if (s.includes('await app.register(m2Orders)')) {
    s = insertAfter(s, 'await app.register(m2Orders)', 'await app.register(m2MSI)');
  } else {
    s += '\nawait app.register(m2MSI)\n';
  }
}

fs.writeFileSync(path, s, 'utf8');
console.log('Patched server.js with MSI');
NODE

# ────────────────────────────────────────────────────────────────────────────────
# Restart + smokes
# ────────────────────────────────────────────────────────────────────────────────
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
fi
: > "$LOG"
( cd "$API" && nohup npm run start > "../$LOG" 2>&1 & echo $! > "../$PIDF" )
sleep 1

echo "⚙️ Flags:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/feature-flags" | jq -c . || true
echo "🧭 Routes:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/debug/routes" | sed -n '1,120p' || true

# Smoke: hent MSI source-items for TEST (bytt SKU om nødvendig)
echo "📦 MSI source-items (TEST):"; curl -sS --max-time 10 "http://127.0.0.1:$PORT/v2/integrations/magento/msi/source-items/TEST" | jq -c . || true

# Smoke: salable qty (stockId=1)
echo "📊 MSI salable qty (TEST):"; curl -sS --max-time 10 "http://127.0.0.1:$PORT/v2/integrations/magento/msi/salable-qty/TEST?stockId=1" | jq -c . || true

echo "✅ MSI install complete."
