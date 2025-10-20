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
