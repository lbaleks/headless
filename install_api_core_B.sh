#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API_DIR="$ROOT/apps/api"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

echo "📦 API_DIR: $API_DIR"
test -d "$API_DIR/src/plugins" || mkdir -p "$API_DIR/src/plugins"

# ────────────────────────────────────────────────────────────────────────────────
# Utilities (shared tiny helper, ESM)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API_DIR/src/plugins/_m2util.js" <<'JS'
import { fetch } from 'undici'
import 'dotenv/config'

export const BASE = process.env.M2_BASE_URL || ''
export const TOKEN = process.env.M2_ADMIN_TOKEN || ''

export function ensureEnv() {
  const miss = []
  if (!BASE) miss.push('M2_BASE_URL')
  if (!TOKEN) miss.push('M2_ADMIN_TOKEN (Integration Token)')
  return miss
}

export async function m2Req(method, path, body, headers = {}) {
  const url = `${BASE}${path}`
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
      ...headers
    },
    body: body ? JSON.stringify(body) : undefined
  })
  const text = await res.text()
  let data
  try { data = JSON.parse(text) } catch { data = { raw: text } }
  if (!res.ok) {
    const err = new Error(`Upstream ${res.status}`)
    err.status = res.status
    err.data = data
    throw err
  }
  return data
}

export const m2Get = (p, h) => m2Req('GET', p, null, h)
export const m2Post = (p, b, h) => m2Req('POST', p, b, h)
export const m2Put  = (p, b, h) => m2Req('PUT',  p, b, h)
JS

# ────────────────────────────────────────────────────────────────────────────────
# Customers plugin (list/get)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API_DIR/src/plugins/magento2.customers.js" <<'JS'
import { ensureEnv, m2Get } from './_m2util.js'

export default async function magentoCustomers(app) {
  app.get('/v2/integrations/magento/customers', async (req) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }

    const { page = 1 } = req.query
    const pageSize = req.query.pageSize ?? req.query.pagesize ?? 20
    const q = req.query.q ?? req.query.query ?? '' // name/email search (like)

    const params = new URLSearchParams()
    params.set('searchCriteria[currentPage]', String(page))
    params.set('searchCriteria[pageSize]', String(pageSize))
    if (q) {
      // simple like on email
      params.set('searchCriteria[filter_groups][0][filters][0][field]', 'email')
      params.set('searchCriteria[filter_groups][0][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][0][filters][0][condition_type]', 'like')
    }

    try {
      const data = await m2Get(`/rest/V1/customers/search?${params.toString()}`)
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:data.total_count ?? (data.items?.length||0), items:data.items||[] }
    } catch (e) {
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:0, items:[], note:'upstream_failed', error:e.data }
    }
  })

  app.get('/v2/integrations/magento/customers/:id', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { id } = req.params
    try {
      const item = await m2Get(`/rest/V1/customers/${encodeURIComponent(id)}`)
      return { ok:true, item }
    } catch (e) {
      reply.code(404); return { ok:false, note:'not_found_or_upstream_failed', error:e.data }
    }
  })
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# Orders plugin (list/get + invoice/creditmemo passthrough)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API_DIR/src/plugins/magento2.orders.js" <<'JS'
import { ensureEnv, m2Get, m2Post } from './_m2util.js'

export default async function magentoOrders(app) {
  // admin gate for mutations
  app.addHook('onRequest', async (req, reply) => {
    if (req.method !== 'GET' && req.url.startsWith('/v2/integrations/magento/orders/')) {
      const role = req.headers['x-role']
      if (role !== 'admin') {
        reply.code(403)
        return reply.send({ ok:false, code:'forbidden', title:'Admin role required' })
      }
    }
  })

  app.get('/v2/integrations/magento/orders', async (req) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }

    const { page = 1 } = req.query
    const pageSize = req.query.pageSize ?? req.query.pagesize ?? 20
    const q = req.query.q ?? req.query.query ?? '' // search by increment_id like
    const params = new URLSearchParams()
    params.set('searchCriteria[currentPage]', String(page))
    params.set('searchCriteria[pageSize]', String(pageSize))
    if (q) {
      params.set('searchCriteria[filter_groups][0][filters][0][field]', 'increment_id')
      params.set('searchCriteria[filter_groups][0][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][0][filters][0][condition_type]', 'like')
    }
    try {
      const data = await m2Get(`/rest/V1/orders?${params.toString()}`)
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:data.total_count ?? (data.items?.length||0), items:data.items||[] }
    } catch (e) {
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:0, items:[], note:'upstream_failed', error:e.data }
    }
  })

  app.get('/v2/integrations/magento/orders/:id', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { id } = req.params
    try {
      const item = await m2Get(`/rest/V1/orders/${encodeURIComponent(id)}`)
      return { ok:true, item }
    } catch (e) {
      reply.code(404); return { ok:false, note:'not_found_or_upstream_failed', error:e.data }
    }
  })

  // Create invoice (simple passthrough) – supports Idempotency-Key passthrough to M2 if configured
  app.post('/v2/integrations/magento/orders/:id/invoice', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return reply.code(400).send({ ok:false, note:'env_missing', missing:miss })
    const { id } = req.params
    const idem = req.headers['idempotency-key']
    try {
      // Payload may be optional/minimal; if your M2 needs items/notify, pass from body
      const payload = req.body && Object.keys(req.body).length ? req.body : { capture: true }
      const data = await m2Post(`/rest/V1/order/${encodeURIComponent(id)}/invoice`, payload, idem ? { 'Idempotency-Key': idem } : undefined)
      return { ok:true, invoice:data }
    } catch (e) {
      reply.code(502); return { ok:false, code:'upstream_failed', detail:e.data }
    }
  })

  // Create credit memo (refund) – minimal passthrough
  app.post('/v2/integrations/magento/orders/:id/creditmemo', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return reply.code(400).send({ ok:false, note:'env_missing', missing:miss })
    const { id } = req.params
    const idem = req.headers['idempotency-key']
    try {
      const payload = req.body && Object.keys(req.body).length ? req.body : { notify: true }
      const data = await m2Post(`/rest/V1/order/${encodeURIComponent(id)}/refund`, payload, idem ? { 'Idempotency-Key': idem } : undefined)
      return { ok:true, creditmemo:data }
    } catch (e) {
      reply.code(502); return { ok:false, code:'upstream_failed', detail:e.data }
    }
  })
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# Categories plugin (tree + rename/active)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API_DIR/src/plugins/magento2.categories.js" <<'JS'
import { ensureEnv, m2Get, m2Put } from './_m2util.js'

export default async function magentoCategories(app) {
  app.get('/v2/integrations/magento/categories/tree', async (req) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { depth = 3 } = req.query
    try {
      const data = await m2Get(`/rest/V1/categories?depth=${encodeURIComponent(depth)}`)
      return { ok:true, tree:data }
    } catch (e) {
      return { ok:false, note:'upstream_failed', error:e.data }
    }
  })

  app.addHook('onRequest', async (req, reply) => {
    if (req.method !== 'GET' && req.url.startsWith('/v2/integrations/magento/categories/')) {
      const role = req.headers['x-role']
      if (role !== 'admin') { reply.code(403); return reply.send({ ok:false, code:'forbidden', title:'Admin role required' }) }
    }
  })

  // Rename category
  app.put('/v2/integrations/magento/categories/:id/name', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return reply.code(400).send({ ok:false, note:'env_missing', missing:miss })
    const { id } = req.params
    const { name } = req.body ?? {}
    if (!name || typeof name !== 'string') { reply.code(400); return { ok:false, code:'bad_request', title:'name:string required' } }
    try {
      const payload = { category: { name } }
      const res = await m2Put(`/rest/V1/categories/${encodeURIComponent(id)}`, payload)
      return { ok:true, updated:{ id, name }, upstream: res.id ? { id: res.id } : undefined }
    } catch (e) {
      reply.code(502); return { ok:false, code:'upstream_failed', detail:e.data }
    }
  })

  // Toggle active
  app.put('/v2/integrations/magento/categories/:id/active', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return reply.code(400).send({ ok:false, note:'env_missing', missing:miss })
    const { id } = req.params
    const { active } = req.body ?? {}
    if (typeof active !== 'boolean') { reply.code(400); return { ok:false, code:'bad_request', title:'active:boolean required' } }
    try {
      const payload = { category: { is_active: active } }
      const res = await m2Put(`/rest/V1/categories/${encodeURIComponent(id)}`, payload)
      return { ok:true, updated:{ id, active }, upstream: res.id ? { id: res.id } : undefined }
    } catch (e) {
      reply.code(502); return { ok:false, code:'upstream_failed', detail:e.data }
    }
  })
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# Sales rules plugin (list/get + enable/disable)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API_DIR/src/plugins/magento2.salesrules.js" <<'JS'
import { ensureEnv, m2Get, m2Put } from './_m2util.js'

export default async function magentoSalesRules(app) {
  app.get('/v2/integrations/magento/sales-rules', async (req) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }

    const { page = 1 } = req.query
    const pageSize = req.query.pageSize ?? req.query.pagesize ?? 20
    const params = new URLSearchParams()
    params.set('searchCriteria[currentPage]', String(page))
    params.set('searchCriteria[pageSize]', String(pageSize))
    try {
      const data = await m2Get(`/rest/V1/salesRules/search?${params.toString()}`)
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:data.total_count ?? (data.items?.length||0), items:data.items||[] }
    } catch (e) {
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:0, items:[], note:'upstream_failed', error:e.data }
    }
  })

  app.get('/v2/integrations/magento/sales-rules/:id', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { id } = req.params
    try {
      const item = await m2Get(`/rest/V1/salesRules/${encodeURIComponent(id)}`)
      return { ok:true, item }
    } catch (e) {
      reply.code(404); return { ok:false, note:'not_found_or_upstream_failed', error:e.data }
    }
  })

  app.addHook('onRequest', async (req, reply) => {
    if (req.method !== 'GET' && req.url.startsWith('/v2/integrations/magento/sales-rules/')) {
      const role = req.headers['x-role']
      if (role !== 'admin') { reply.code(403); return reply.send({ ok:false, code:'forbidden', title:'Admin role required' }) }
    }
  })

  app.put('/v2/integrations/magento/sales-rules/:id/enabled', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return reply.code(400).send({ ok:false, note:'env_missing', missing:miss })
    const { id } = req.params
    const { enabled } = req.body ?? {}
    if (typeof enabled !== 'boolean') { reply.code(400); return { ok:false, code:'bad_request', title:'enabled:boolean required' } }
    try {
      const payload = { rule: { is_active: enabled } }
      const res = await m2Put(`/rest/V1/salesRules/${encodeURIComponent(id)}`, payload)
      return { ok:true, updated:{ id, enabled }, upstream: res.rule_id ? { id: res.rule_id } : undefined }
    } catch (e) {
      reply.code(502); return { ok:false, code:'upstream_failed', detail:e.data }
    }
  })
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# Update feature-flags (idempotent: overwrite with superset)
# ────────────────────────────────────────────────────────────────────────────────
cat > "$API_DIR/src/plugins/feature-flags.js" <<'JS'
export default async function featureFlagsPlugin (app) {
  app.get('/v2/feature-flags', async () => ({
    ok: true,
    flags: {
      m2_products: true,
      m2_mutations: true,
      m2_customers: true,
      m2_orders: true,
      m2_categories: true,
      m2_sales_rules: true
    }
  }))
}
JS

# ────────────────────────────────────────────────────────────────────────────────
# Patch server.js to import/register new plugins exactly once
# ────────────────────────────────────────────────────────────────────────────────
SV="$API_DIR/src/server.js"

# Ensure import lines
grep -q "magento2.customers.js" "$SV" || sed -i '' '1 a\
import m2Customers from '"'"'./plugins/magento2.customers.js'"'"'\
' "$SV"
grep -q "magento2.orders.js" "$SV" || sed -i '' '1 a\
import m2Orders from '"'"'./plugins/magento2.orders.js'"'"'\
' "$SV"
grep -q "magento2.categories.js" "$SV" || sed -i '' '1 a\
import m2Categories from '"'"'./plugins/magento2.categories.js'"'"'\
' "$SV"
grep -q "magento2.salesrules.js" "$SV" || sed -i '' '1 a\
import m2SalesRules from '"'"'./plugins/magento2.salesrules.js'"'"'\
' "$SV"

# Register after existing plugins
grep -q "register(m2Customers)" "$SV" || sed -i '' $'/await app.register(magento2)/a\\\nawait app.register(m2Customers)\\\nawait app.register(m2Orders)\\\nawait app.register(m2Categories)\\\nawait app.register(m2SalesRules)\n' "$SV"

# ────────────────────────────────────────────────────────────────────────────────
# Safe restart + smoke
# ────────────────────────────────────────────────────────────────────────────────
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  echo "🧹 Stopper prosess på port $PORT"
  lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
fi
: > "$LOG"
echo "🚀 Starter API…"
( cd "$API_DIR" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1.2

echo "🩺 Health:";        curl -sS --max-time 3 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true
echo "⚙️  Flags:";        curl -sS --max-time 3 "http://127.0.0.1:$PORT/v2/feature-flags" | jq -c . || true
echo "🧭 Routes:";       curl -sS --max-time 3 "http://127.0.0.1:$PORT/v2/debug/routes" || true

echo "👤 Customers:";    curl -sS --max-time 8 "http://127.0.0.1:$PORT/v2/integrations/magento/customers?page=1&pageSize=2&q=@gmail" | jq -c . || true
echo "📦 Orders:";       curl -sS --max-time 8 "http://127.0.0.1:$PORT/v2/integrations/magento/orders?page=1&pageSize=2&q=10" | jq -c . || true
echo "🗂  Categories:";  curl -sS --max-time 8 "http://127.0.0.1:$PORT/v2/integrations/magento/categories/tree?depth=2" | jq -c . || true
echo "🏷️  SalesRules:";  curl -sS --max-time 8 "http://127.0.0.1:$PORT/v2/integrations/magento/sales-rules?page=1&pageSize=2" | jq -c . || true

echo "✅ Milepæl B ferdig."
