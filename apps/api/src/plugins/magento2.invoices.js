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
