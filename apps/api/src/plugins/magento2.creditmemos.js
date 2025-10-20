import { ensureEnv, m2Get } from './_m2util.js'

export default async function magentoCreditMemos(app) {
  app.get('/v2/integrations/magento/creditmemos/:id', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { id } = req.params
    try {
      const cm = await m2Get(`/rest/V1/creditmemo/${encodeURIComponent(id)}`)
      return { ok:true, creditmemo: cm }
    } catch (e) {
      reply.code(404); return { ok:false, note:'not_found_or_upstream_failed', error:e.data }
    }
  })

  // Enkel list: filtrer på order_id hvis oppgitt
  app.get('/v2/integrations/magento/creditmemos', async (req) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { order_id } = req.query
    // Magento har ikke en offisiell search for creditmemos i standard REST (varierer med versjon/eksponering),
    // så vi bruker workaround: hent fra ordre-ressursens creditmemos hvis tilgjengelig; ellers 501.
    if (!order_id) {
      return { ok:false, note:'not_supported', title:'Provide order_id query param to list credit memos for an order' }
    }
    try {
      // Prøv å hente ordre; noen installasjoner returnerer creditmemos under extension_attributes
      const ord = await m2Get(`/rest/V1/orders/${encodeURIComponent(order_id)}`)
      const ext = ord.extension_attributes || {}
      const list = ext.credit_memos || ext.credits || []
      return { ok:true, order_id: Number(order_id), items: Array.isArray(list) ? list : [] }
    } catch (e) {
      return { ok:false, note:'upstream_failed', error:e.data }
    }
  })
}
