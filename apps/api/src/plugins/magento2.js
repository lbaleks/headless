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
