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
