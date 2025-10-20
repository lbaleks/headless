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
