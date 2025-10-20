import { ensureEnv, m2Get, m2Post } from './_m2util.js'

function toInt01(v) { return v ? 1 : 0 }

export default async function creditHelper(app) {
  // Admin gate (mutations)
  app.addHook('onRequest', async (req, reply) => {
    if (req.method !== 'GET' && req.url.startsWith('/v2/integrations/magento/orders/')) {
      const role = req.headers['x-role'] || (req.user && req.user.role)
      if (role !== 'admin') {
        reply.code(403)
        return reply.send({ ok:false, code:'forbidden', title:'Admin role required' })
      }
    }
  })

  // GET preview av refunderbare linjer
  app.get('/v2/integrations/magento/orders/:id/refundable', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return { ok:false, note:'env_missing', missing:miss }
    const { id } = req.params
    try {
      const ord = await m2Get(`/rest/V1/orders/${encodeURIComponent(id)}`)
      const items = (ord.items || []).map(it => {
        const inv = Number(it.qty_invoiced || 0)
        const ref = Number(it.qty_refunded || 0)
        return {
          order_item_id: it.item_id,
          name: it.name,
          qty_invoiced: inv,
          qty_refunded: ref,
          qty_refundable: Math.max(0, inv - ref)
        }
      }).filter(x => x.qty_refundable > 0)
      return { ok:true, order_id: Number(id), items }
    } catch (e) {
      reply.code(404)
      return { ok:false, note:'not_found_or_upstream_failed', error: e.data }
    }
  })

  // POST full refund (auto build payload)
  app.post('/v2/integrations/magento/orders/:id/creditmemo/full', async (req, reply) => {
    const miss = ensureEnv()
    if (miss.length) return reply.code(400).send({ ok:false, note:'env_missing', missing:miss })
    const { id } = req.params
    const q = req.query || {}
    const body = req.body || {}

    // Tolerante parametre
    const notify = body.notify ?? q.notify ?? false
    const appendComment = body.appendComment ?? q.appendComment ?? false
    const commentText = (body.comment?.comment) ?? q.comment ?? ''
    const isVisibleOnFront = toInt01((body.comment?.is_visible_on_front) ?? q.is_visible_on_front ?? 0)
    const refundShipping = body.refund_shipping ?? q.refund_shipping ?? false
    const adjPos = Number(body.adjustment_positive ?? q.adjustment_positive ?? 0)
    const adjNeg = Number(body.adjustment_negative ?? q.adjustment_negative ?? 0)
    const dryRun = body.dry_run ?? q.dry_run ?? false

    try {
      const ord = await m2Get(`/rest/V1/orders/${encodeURIComponent(id)}`)
      const items = (ord.items || []).map(it => {
        const inv = Number(it.qty_invoiced || 0)
        const ref = Number(it.qty_refunded || 0)
        const can = Math.max(0, inv - ref)
        return can > 0 ? { order_item_id: it.item_id, qty: can } : null
      }).filter(Boolean)

      if (!items.length) {
        reply.code(400)
        return { ok:false, code:'nothing_to_refund', title:'No refundable quantity on this order' }
      }

      const payload = {
        items,
        notify: !!notify,
        appendComment: !!appendComment,
        ...(appendComment ? { comment: { comment: String(commentText || ''), is_visible_on_front: isVisibleOnFront } } : {}),
        arguments: {
          shipping_amount: refundShipping ? Number(ord.shipping_incl_tax || ord.shipping_amount || 0) : 0,
          adjustment_positive: isFinite(adjPos) ? adjPos : 0,
          adjustment_negative: isFinite(adjNeg) ? adjNeg : 0
        }
      }

      if (dryRun) {
        return { ok:true, dry_run:true, order_id: Number(id), payload }
      }

      const headers = {}
      const idem = req.headers['idempotency-key']
      if (idem) headers['Idempotency-Key'] = idem

      const res = await m2Post(`/rest/V1/order/${encodeURIComponent(id)}/refund`, payload, headers)
      // Mange M2 returnerer entity_id eller objekt; normaliser lite svar
      const cmId = (typeof res === 'object' && res?.entity_id) ? res.entity_id : res
      return { ok:true, order_id: Number(id), creditmemo: cmId || true, upstream: res }
    } catch (e) {
      reply.code(e.status || 502)
      return { ok:false, code:'upstream_failed', detail: e.data || String(e) }
    }
  })
}
