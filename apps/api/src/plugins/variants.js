import { fetch } from 'undici'
import 'dotenv/config'
const BASE = process.env.M2_BASE_URL || ''
const TOKEN = process.env.M2_ADMIN_TOKEN || ''

async function m2Get(path) {
  const r = await fetch(`${BASE}${path}`, { headers: { Authorization: `Bearer ${TOKEN}` } })
  const t = await r.text()
  let j; try { j = JSON.parse(t) } catch { j = { raw:t } }
  if (!r.ok) throw Object.assign(new Error(`Upstream ${r.status}`), { status:r.status, data:j })
  return j
}

export default async function variants(app) {
  // feature flag legger vi her for enkelhets skyld (kombinerer med eksisterende flags i UI)
  app.addHook('onReady', async function(){
    app.__flags = app.__flags || {}
    app.__flags.m2_variants = true
  })

  // GET children for configurable
  app.get('/v2/integrations/magento/products/:sku/variants', async (req, reply) => {
    const { sku } = req.params
    try {
      // Primær: configurable children
      const children = await m2Get(`/rest/V1/configurable-products/${encodeURIComponent(sku)}/children`)
      if (Array.isArray(children) && children.length) {
        const items = children.map(c => ({
          id: c.id, sku: c.sku, name: c.name, price: c.price, status: c.status, type: c.type_id
        }))
        return { ok:true, source:'configurable-children', items }
      }
      // Fallback: les hovedprodukt og sjekk product_links
      const prod = await m2Get(`/rest/V1/products/${encodeURIComponent(sku)}`)
      const links = prod.product_links || []
      const simples = links.filter(l => l.link_type === 'associated')
      if (simples.length) {
        // Hent hver (kan optimaliseres siden M2 ikke har bulk-by-sku standard her)
        const items = []
        for (const l of simples.slice(0,25)) {
          try {
            const c = await m2Get(`/rest/V1/products/${encodeURIComponent(l.linked_product_sku)}`)
            items.push({ id:c.id, sku:c.sku, name:c.name, price:c.price, status:c.status, type:c.type_id })
          } catch {}
        }
        return { ok:true, source:'product_links', items }
      }
      return { ok:true, source:'none', items:[] }
    } catch (e) {
      reply.code(502); return { ok:false, note:'upstream_failed', error:e.data||String(e) }
    }
  })
}
