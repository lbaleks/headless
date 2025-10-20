import '../env-load.js'

let MAP = {}
try { MAP = JSON.parse(process.env.RBAC_API_KEYS || '{}') } catch { MAP = {} }
const VALID = new Set(['admin','reader'])

export default async function rbac(app) {
  app.addHook('onRequest', async (req, reply) => {
    const apiKey = req.headers['x-api-key']
    let role = apiKey && MAP[apiKey]
    if (!role && process.env.NODE_ENV !== 'production') {
      const devRole = req.headers['x-role']
      if (VALID.has(devRole)) role = devRole
    }
    if (!role) role = 'reader'
    if (req.method !== 'GET' && role !== 'admin') {
      reply.code(403)
      return reply.send({ ok:false, code:'forbidden', title:'Admin role required', hint:'Provide x-api-key for admin' })
    }
    req.user = { role }
  })
  app.get('/v2/auth/whoami', async (req) => ({ ok:true, role: req.user?.role || 'reader' }))
}
