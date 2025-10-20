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
    const err = new Error(`Upstream ${r.status}`)
    err.status = r.status
    err.data = data
    throw err
  }
  return data
}

export default async function magentoOrders(app) {
  // Orders list (supports page/pageSize + q tolerant)
  app.get('/v2/integrations/magento/orders', async (req) => {
    const miss = badEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing: miss }

    const { page = 1 } = req.query
    const pageSize = req.query.pageSize ?? req.query.pagesize ?? 10
    const q = req.query.q ?? req.query.query ?? ''

    const params = new URLSearchParams()
    params.set('searchCriteria[currentPage]', String(page))
    params.set('searchCriteria[pageSize]', String(pageSize))

    if (q) {
      // enkel søk: match increment_id like eller status like
      // NOTE: Magento støtter OR ved flere filter_groups
      params.set('searchCriteria[filter_groups][0][filters][0][field]', 'increment_id')
      params.set('searchCriteria[filter_groups][0][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][0][filters][0][condition_type]', 'like')

      params.set('searchCriteria[filter_groups][1][filters][0][field]', 'status')
      params.set('searchCriteria[filter_groups][1][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][1][filters][0][condition_type]', 'like')
    }

    try {
      const data = await m2Get(`/rest/V1/orders?${params.toString()}`)
      const items = data.items ?? []
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:data.total_count ?? items.length, items }
    } catch (e) {
      return { ok:true, page:Number(page), pageSize:Number(pageSize), total:0, items:[], note:'upstream_failed', error:e.data }
    }
  })

  // Single order by entity_id
  app.get('/v2/integrations/magento/orders/:id', async (req, reply) => {
    const miss = badEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing: miss }

    const { id } = req.params
    try {
      const item = await m2Get(`/rest/V1/orders/${encodeURIComponent(id)}`)
      return { ok:true, item }
    } catch (e) {
      reply.code(404)
      return { ok:false, note:'not_found_or_upstream_failed', error:e.data }
    }
  })
}
