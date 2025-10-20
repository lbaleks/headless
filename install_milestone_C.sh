#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

mkdir -p "$API/src/plugins" "$API/src/docs"

# ────────────────────────────────────────────────────────────────────────────────
# 0) RBAC-konfig i .env (idempotent append, endre verdier etter behov)
# ────────────────────────────────────────────────────────────────────────────────
if ! grep -q "^RBAC_API_KEYS=" "$ROOT/.env"; then
  cat >> "$ROOT/.env" <<'ENV'

# --- RBAC (API keys => role) ---
# JSON: { "apikey123": "admin", "readonly456": "reader" }
RBAC_API_KEYS={"dev-admin-key":"admin","dev-readonly-key":"reader"}
ENV
fi

# ────────────────────────────────────────────────────────────────────────────────
# 1) RBAC plugin: x-api-key -> role (admin|reader); beholder x-role override i dev
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API/src/plugins/auth.rbac.js" <<'JS'
import '../env-load.js'

let MAP = {}
try {
  MAP = JSON.parse(process.env.RBAC_API_KEYS || '{}')
} catch { MAP = {} }

const VALID = new Set(['admin','reader'])

export default async function rbac(app) {
  app.addHook('onRequest', async (req, reply) => {
    // 1) x-api-key (prod-vei)
    const apiKey = req.headers['x-api-key']
    let role = apiKey && MAP[apiKey]

    // 2) dev override (kompat med eksisterende flows)
    if (!role && process.env.NODE_ENV !== 'production') {
      const devRole = req.headers['x-role']
      if (VALID.has(devRole)) role = devRole
    }

    // default til reader hvis ikke satt (kun GET)
    if (!role) role = 'reader'

    // policy: muterende kall krever admin
    if (req.method !== 'GET' && role !== 'admin') {
      reply.code(403)
      return reply.send({ ok:false, code:'forbidden', title:'Admin role required', hint:'Provide x-api-key for admin' })
    }

    // eksponer rollen til ruter
    req.user = { role }
  })

  // introspeksjon (GET)
  app.get('/v2/auth/whoami', async (req) => ({ ok:true, role: req.user?.role || 'reader' }))
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# 2) OpenAPI: statisk spec + enkel docs-side
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API/src/docs/openapi.json" <<'JSON'
{
  "openapi": "3.0.3",
  "info": { "title": "Litebrygg Admin API (v2)", "version": "0.3.0" },
  "servers": [{ "url": "http://127.0.0.1:3044" }],
  "components": {
    "securitySchemes": {
      "apiKeyAuth": { "type": "apiKey", "name": "x-api-key", "in": "header" }
    }
  },
  "security": [{ "apiKeyAuth": [] }],
  "paths": {
    "/v2/health": { "get": { "summary": "Health", "responses": { "200": { "description": "OK" }}}},
    "/v2/feature-flags": { "get": { "summary": "Flags", "responses": { "200": { "description": "OK" }}}},
    "/v2/auth/whoami": { "get": { "summary": "Who am I (role)", "responses": { "200": { "description": "OK" }}}},
    "/v2/integrations/magento/products": { "get": { "summary": "List products", "parameters": [{ "name":"page","in":"query"},{ "name":"pageSize","in":"query"},{ "name":"q","in":"query"}], "responses": { "200": { "description": "OK" }}}},
    "/v2/integrations/magento/products/{sku}": { "get": { "summary": "Get product", "parameters": [{ "name":"sku","in":"path","required":true }], "responses": { "200": { "description": "OK" }, "404": { "description": "Not found" }}}},
    "/v2/integrations/magento/products/{sku}/price": { "put": { "summary": "Update price (admin)", "responses": { "200": { "description": "OK" }, "403": { "description": "Forbidden" }}}},
    "/v2/integrations/magento/products/{sku}/stock": { "put": { "summary": "Update stock (admin)", "responses": { "200": { "description": "OK" }, "403": { "description": "Forbidden" }}}},
    "/v2/integrations/magento/products/{sku}/status": { "put": { "summary": "Update status (admin)", "responses": { "200": { "description": "OK" }, "403": { "description": "Forbidden" }}}},
    "/v2/integrations/magento/customers": { "get": { "summary": "List customers", "parameters": [{ "name":"page","in":"query"},{ "name":"pageSize","in":"query"},{ "name":"q","in":"query"}], "responses": { "200": { "description": "OK" }}}},
    "/v2/integrations/magento/orders": { "get": { "summary": "List orders", "parameters": [{ "name":"page","in":"query"},{ "name":"pageSize","in":"query"},{ "name":"q","in":"query"}], "responses": { "200": { "description": "OK" }}}},
    "/v2/integrations/magento/orders/{id}": { "get": { "summary": "Get order", "responses": { "200": { "description": "OK" }, "404": { "description": "Not found" }}}},
    "/v2/integrations/magento/orders/{id}/invoice": { "post": { "summary": "Create invoice (admin)", "responses": { "200": { "description": "OK" }, "403": { "description": "Forbidden" }}}},
    "/v2/integrations/magento/orders/{id}/creditmemo": { "post": { "summary": "Create credit memo (admin)", "responses": { "200": { "description": "OK" }, "403": { "description": "Forbidden" }}}},
    "/v2/integrations/magento/categories/tree": { "get": { "summary": "Categories tree", "parameters": [{ "name":"depth","in":"query"}], "responses": { "200": { "description": "OK" }}}},
    "/v2/integrations/magento/sales-rules": { "get": { "summary": "List sales rules", "responses": { "200": { "description": "OK" }}}},
    "/v2/integrations/magento/sales-rules/{id}/enabled": { "put": { "summary": "Toggle sales rule (admin)", "responses": { "200": { "description": "OK" }, "403": { "description": "Forbidden" }}}},
    "/v2/integrations/magento/creditmemos/{id}": { "get": { "summary": "Get credit memo", "responses": { "200": { "description": "OK" }, "404": { "description": "Not found" }}}},
    "/v2/integrations/magento/creditmemos": { "get": { "summary": "List credit memos (order_id required; best effort)", "parameters": [{ "name":"order_id","in":"query"}], "responses": { "200": { "description": "OK" }}}}
  }
}
JSON

cat > "$API/src/plugins/openapi.js" <<'JS'
import fs from 'fs'
import path from 'path'

export default async function openapi(app) {
  app.get('/v2/openapi.json', async (req, reply) => {
    const p = path.resolve(process.cwd(), 'src/docs/openapi.json')
    const buf = fs.readFileSync(p)
    reply.header('content-type','application/json; charset=utf-8')
    return reply.send(buf)
  })

  // Minimal docs (Redoc via CDN – enkel HTML)
  app.get('/v2/docs', async (req, reply) => {
    const html = `<!doctype html>
<html><head><meta charset="utf-8"/><title>Litebrygg Admin API Docs</title>
<script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
<style>body{margin:0} .hdr{padding:10px 14px;background:#0f172a;color:#fff;font-family:ui-sans-serif} .hdr code{background:#111827;padding:2px 6px;border-radius:6px}</style>
</head><body>
<div class="hdr">Litebrygg Admin API – <code>/v2/openapi.json</code></div>
<redoc spec-url="/v2/openapi.json"></redoc>
</body></html>`
    reply.type('text/html').send(html)
  })
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# 3) Invoices plugin (lesing via Magento)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API/src/plugins/magento2.invoices.js" <<'JS'
import { ensureEnv, m2Get } from './_m2util.js'

export default async function magentoInvoices(app) {
  app.get('/v2/integrations/magento/invoices/:id', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { id } = req.params
    try {
      const inv = await m2Get(`/rest/V1/invoices/${encodeURIComponent(id)}`)
      return { ok:true, invoice: inv }
    } catch (e) {
      reply.code(404); return { ok:false, note:'not_found_or_upstream_failed', error:e.data }
    }
  })

  // Standard M2 støtter /V1/invoices?searchCriteria=...
  app.get('/v2/integrations/magento/invoices', async (req) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { page = 1 } = req.query
    const pageSize = req.query.pageSize ?? req.query.pagesize ?? 20
    const params = new URLSearchParams()
    params.set('searchCriteria[currentPage]', String(page))
    params.set('searchCriteria[pageSize]', String(pageSize))
    try {
      const data = await m2Get(`/rest/V1/invoices?${params.toString()}`)
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:data.total_count ?? (data.items?.length||0), items:data.items||[] }
    } catch (e) {
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:0, items:[], note:'upstream_failed', error:e.data }
    }
  })
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# 4) Oppdatér feature-flags (superset)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API/src/plugins/feature-flags.js" <<'JS'
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
      openapi: true
    }
  }))
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# 5) Patch server.js: importer/registrer nye plugins (idempotent)
# ────────────────────────────────────────────────────────────────────────────────
SV="$API/src/server.js"

add_import() {
  local sym="$1"; local file="$2"
  grep -q "$file" "$SV" || sed -i '' "1 a\\
import $sym from '$file'\\
" "$SV"
}

add_import rbac "./plugins/auth.rbac.js"
add_import openapi "./plugins/openapi.js"
add_import m2Invoices "./plugins/magento2.invoices.js"

# Registrer etter eksisterende registreringer
grep -q "register(rbac)" "$SV" || sed -i '' $'/await app.register(cors[^\)]*\\)\\)/a\\
await app.register(rbac)\\
' "$SV"

grep -q "register(openapi)" "$SV" || sed -i '' $'/await app.register(m2SalesRules)/a\\
await app.register(openapi)\\
' "$SV"

grep -q "register(m2Invoices)" "$SV" || sed -i '' $'/await app.register(m2CreditMemos)/a\\
await app.register(m2Invoices)\\
' "$SV"

# ────────────────────────────────────────────────────────────────────────────────
# 6) Restart + Smokes
# ────────────────────────────────────────────────────────────────────────────────
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1

echo "🩺 Health:";        curl -sS --max-time 5 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true
echo "🔑 Whoami:";        curl -sS --max-time 5 -H 'x-api-key: dev-admin-key' "http://127.0.0.1:$PORT/v2/auth/whoami" | jq -c . || true
echo "📜 OpenAPI:";       curl -sS --max-time 5 "http://127.0.0.1:$PORT/v2/openapi.json" | jq -c '.info.version,.paths|keys|length' || true
echo "📄 Docs page:";     echo "http://127.0.0.1:$PORT/v2/docs"
echo "🧾 Invoice(id=1):"; curl -sS --max-time 8 "http://127.0.0.1:$PORT/v2/integrations/magento/invoices/1" | jq -c '.ok, .invoice?.entity_id' || true
echo "🧾 Invoices list:"; curl -sS --max-time 8 "http://127.0.0.1:$PORT/v2/integrations/magento/invoices?page=1&pageSize=2" | jq -c '.ok, .total' || true
echo "✅ Milepæl C ferdig."
