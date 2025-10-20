#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API_DIR="$ROOT/apps/api"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

echo "📦 API_DIR: $API_DIR"
mkdir -p "$API_DIR/src/plugins"

# ── package.json (egen, ren API-app – unngår Next/webpack-støy)
if [ ! -f "$API_DIR/package.json" ]; then
  cat > "$API_DIR/package.json" <<'JSON'
{
  "name": "@litebrygg/api",
  "private": true,
  "type": "module",
  "version": "0.1.0",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "@fastify/cors": "^9.0.1",
    "dotenv": "^16.4.5",
    "fastify": "^4.28.1",
    "undici": "^6.19.8"
  }
}
JSON
fi

echo "🧩 Installerer avhengigheter (ren API-app)…"
(cd "$API_DIR" && npm i --silent)

# ── feature-flags plugin (stub)
cat > "$API_DIR/src/plugins/feature-flags.js" <<'JS'
export default async function featureFlagsPlugin (app) {
  app.get('/v2/feature-flags', async () => ({
    ok: true,
    flags: {
      m2_products: true,
      m2_mutations: true
    }
  }))
}
JS

# ── magento2 plugin (produkter: ping, list, get, put: price/stock/status)
cat > "$API_DIR/src/plugins/magento2.js" <<'JS'
import { fetch } from 'undici'
import 'dotenv/config'

const BASE = process.env.M2_BASE_URL || ''
const TOKEN = process.env.M2_ADMIN_TOKEN || ''

function badEnv() {
  const miss = []
  if (!BASE) miss.push('M2_BASE_URL')
  if (!TOKEN) miss.push('M2_ADMIN_TOKEN (Integration Token)')
  return miss
}

async function m2Get(path) {
  const url = `${BASE}${path}`
  const r = await fetch(url, { headers: { Authorization: `Bearer ${TOKEN}` } })
  const text = await r.text()
  let data
  try { data = JSON.parse(text) } catch { data = { raw: text } }
  if (!r.ok) {
    throw Object.assign(new Error(`Upstream ${r.status}`), { status: r.status, data })
  }
  return data
}

async function m2Put(path, body) {
  const url = `${BASE}${path}`
  const r = await fetch(url, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  })
  const text = await r.text()
  let data
  try { data = JSON.parse(text) } catch { data = { raw: text } }
  if (!r.ok) {
    throw Object.assign(new Error(`Upstream ${r.status}`), { status: r.status, data })
  }
  return data
}

export default async function magento2(app) {
  // Ping/verifisering
  app.get('/v2/integrations/magento/ping', async () => {
    const miss = badEnv()
    if (miss.length) {
      return { ok: false, note: 'env_missing', missing: miss }
    }
    try {
      // Lettvektskall (hent 1 produktside)
      await m2Get('/rest/V1/products?searchCriteria[currentPage]=1&searchCriteria[pageSize]=1')
      return { ok: true, base: BASE }
    } catch (e) {
      return { ok: false, note: 'upstream_failed', error: e.data || String(e) }
    }
  })

  // List produkter
  app.get('/v2/integrations/magento/products', async (req) => {
    const { page = 1 } = req.query
    const pageSize = req.query.pageSize ?? req.query.pagesize ?? 20
    const q = req.query.q ?? req.query.query ?? ''
    const params = new URLSearchParams()
    params.set('searchCriteria[currentPage]', String(page))
    params.set('searchCriteria[pageSize]', String(pageSize))
    if (q) {
      // søk i navn/sku
      params.set('searchCriteria[filter_groups][0][filters][0][field]', 'name')
      params.set('searchCriteria[filter_groups][0][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][0][filters][0][condition_type]', 'like')
    }
    try {
      const data = await m2Get(`/rest/V1/products?${params.toString()}`)
      const items = data.items ?? []
      return { ok: true, page: Number(page), pageSize: Number(pageSize), total: data.total_count ?? items.length, items }
    } catch (e) {
      return { ok: true, page: Number(page), pageSize: Number(pageSize), total: 0, items: [], note: 'upstream_failed', error: e.data }
    }
  })

  // Hent ett produkt
  app.get('/v2/integrations/magento/products/:sku', async (req, reply) => {
    const { sku } = req.params
    try {
      const item = await m2Get(`/rest/V1/products/${encodeURIComponent(sku)}`)
      return { ok: true, item }
    } catch (e) {
      reply.code(404)
      return { ok: false, note: 'not_found_or_upstream_failed', error: e.data }
    }
  })

  // Mutasjoner (enkel paritet) – krever x-role: admin
  app.addHook('onRequest', async (req, reply) => {
    if (req.method !== 'GET' && req.url.startsWith('/v2/integrations/magento/products/')) {
      const role = req.headers['x-role']
      if (role !== 'admin') {
        reply.code(403)
        return reply.send({ ok: false, code: 'forbidden', title: 'Admin role required' })
      }
    }
  })

  // PUT price
  app.put('/v2/integrations/magento/products/:sku/price', async (req, reply) => {
    const { sku } = req.params
    const { price } = req.body ?? {}
    if (typeof price !== 'number') {
      reply.code(400); return { ok: false, code: 'bad_request', title: 'price:number required' }
    }
    try {
      const payload = { product: { sku, price } }
      const res = await m2Put(`/rest/V1/products/${encodeURIComponent(sku)}`, payload)
      return { ok: true, updated: { sku, price }, upstream: res.id ? { id: res.id } : undefined }
    } catch (e) {
      reply.code(502); return { ok: false, code: 'upstream_failed', detail: e.data }
    }
  })

  // PUT stock (via product extension stock_item er ofte via annet endepunkt i M2 – enkel demo)
  app.put('/v2/integrations/magento/products/:sku/stock', async (req, reply) => {
    const { sku } = req.params
    const { stock } = req.body ?? {}
    if (typeof stock !== 'number') {
      reply.code(400); return { ok: false, code: 'bad_request', title: 'stock:number required' }
    }
    try {
      const payload = {
        product: {
          sku,
          extension_attributes: { stock_item: { qty: stock, is_in_stock: stock > 0 } }
        }
      }
      const res = await m2Put(`/rest/V1/products/${encodeURIComponent(sku)}`, payload)
      return { ok: true, updated: { sku, stock }, upstream: res.id ? { id: res.id } : undefined }
    } catch (e) {
      reply.code(502); return { ok: false, code: 'upstream_failed', detail: e.data }
    }
  })

  // PUT status
  app.put('/v2/integrations/magento/products/:sku/status', async (req, reply) => {
    const { sku } = req.params
    const { status } = req.body ?? {}
    const map = { enabled: 1, disabled: 2 }
    if (!['enabled','disabled'].includes(status)) {
      reply.code(400); return { ok: false, code: 'bad_request', title: 'status must be enabled|disabled' }
    }
    try {
      const payload = { product: { sku, status: map[status] } }
      const res = await m2Put(`/rest/V1/products/${encodeURIComponent(sku)}`, payload)
      return { ok: true, updated: { sku, status }, upstream: res.id ? { id: res.id } : undefined }
    } catch (e) {
      reply.code(502); return { ok: false, code: 'upstream_failed', detail: e.data }
    }
  })
}
JS

# ── server.js (ESM, én listen, CORS én gang, auto-register)
cat > "$API_DIR/src/server.js" <<'JS'
import 'dotenv/config'
import Fastify from 'fastify'
import cors from '@fastify/cors'
import featureFlags from './plugins/feature-flags.js'
import magento2 from './plugins/magento2.js'

const PORT = Number(process.env.PORT || 3044)
const ORIGIN = process.env.CORS_ORIGIN || 'http://localhost:3020'

const app = Fastify({ logger: true })

await app.register(cors, { origin: ORIGIN, methods: ['GET','HEAD','POST','PUT','PATCH','OPTIONS'] })

app.get('/v2/health', async () => ({
  ok: true,
  uptime: process.uptime(),
  now: new Date().toISOString(),
  env: process.env.NODE_ENV || 'development'
}))

// debug/routes – tekstlig tre for “øyet”, ikke JSON
app.get('/v2/debug/routes', async () => {
  const lines = []
  lines.push('└── (root)')
  const routes = app.printRoutes({ includeHooks: false })
  lines.push(routes)
  return lines.join('\n')
})

// plugins
await app.register(featureFlags)
await app.register(magento2)

// Lytt KUN én gang
app.listen({ port: PORT, host: '0.0.0.0' }).then(() => {
  app.log.info(`API listening on http://0.0.0.0:${PORT}`)
})
JS

# ── restart trygt
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  echo "🧹 Stopper prosess på port $PORT"
  lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
fi
: > "$LOG"
echo "🚀 Starter API…"
( cd "$API_DIR" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1.2

echo "🩺 Health:"
curl -sS --max-time 3 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true

echo "⚙️  Flags:"
curl -sS --max-time 3 "http://127.0.0.1:$PORT/v2/feature-flags" | jq -c . || true

echo "🧭 Routes (tekst – ikke bruk jq):"
curl -sS --max-time 3 "http://127.0.0.1:$PORT/v2/debug/routes" || true

echo "🔔 M2 Ping:"
curl -sS --max-time 5 "http://127.0.0.1:$PORT/v2/integrations/magento/ping" | jq -c . || true

echo "✅ Ferdig."
