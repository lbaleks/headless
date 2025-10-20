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
