/**
 * Feature flags (volatile in-memory)
 * - GET /v2/feature-flags -> { ok, flags }
 * - PUT /v2/feature-flags  (x-role: admin)
 *      body: { flags: { key: boolean, ... } }
 */
const FLAGS = {
  m2_products: true,
  m2_mutations: true,
  m2_customers: true,
  m2_orders: true,
  m2_categories: true,
  m2_sales_rules: true,
  m2_creditmemos: true,
  m2_invoices: true,
  m2_msi: true,
  rbac: true,
  openapi: true,
  m2_credit_helper: true
}

export default async function featureFlagsPlugin (app) {
  app.get('/v2/feature-flags', async () => ({ ok: true, flags: FLAGS }))

  app.put('/v2/feature-flags', async (req, reply) => {
    const role = req.headers['x-role']
    if (role !== 'admin') {
      reply.code(403)
      return { ok: false, code: 'forbidden', title: 'Admin role required' }
    }
    const body = req.body || {}
    const incoming = body.flags || {}
    const changed = {}
    for (const k of Object.keys(incoming)) {
      if (Object.prototype.hasOwnProperty.call(FLAGS, k)) {
        const v = incoming[k]
        const bool = v === true || v === false || v === 1 || v === 0 || v === 'true' || v === 'false'
        if (bool) {
          const next = (v === true || v === 1 || v === 'true')
          if (FLAGS[k] !== next) {
            FLAGS[k] = next
            changed[k] = next
          }
        }
      }
    }
    return { ok: true, changed, flags: FLAGS }
  })
}
