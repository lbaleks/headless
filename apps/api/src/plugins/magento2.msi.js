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
