/**
 * Activity Log (in-memory)
 * - Logger muterende kall (POST/PUT/PATCH) + Idempotency-Key, duration, status
 * - GET /v2/activity?page=&pageSize=
 * - GET /v2/activity/:id
 * - DELETE /v2/activity  (x-role: admin)
 */
const BUF_MAX = 500
const store = []  // newest last
let seq = 1

function pushEntry(entry) {
  store.push(entry)
  if (store.length > BUF_MAX) store.shift()
}

export default async function activity(app) {
  app.addHook('onRequest', async (req, reply) => {
    const m = req.method
    // Log kun muterende
    if (m === 'POST' || m === 'PUT' || m === 'PATCH' || m === 'DELETE') {
      req.__act = {
        id: String(seq++),
        ts: Date.now(),
        method: m,
        url: req.url,
        role: String(req.headers['x-role'] || 'viewer'),
        idem: String(req.headers['idempotency-key'] || ''),
        body: undefined, // fylles under
        status: undefined,
        ms: undefined
      }
      // Prøv å lese body kort (uten å bremse)
      try {
        // Fastify har allerede parsed body, men her kan den være udefinert
        if (req.body != null) {
          const s = JSON.stringify(req.body)
          req.__act.body = s.length > 2000 ? s.slice(0,2000)+'…' : s
        }
      } catch {}
      req.__act.__start = process.hrtime.bigint()
    }
  })

  app.addHook('onSend', async (req, reply, payload) => {
    const ctx = req.__act
    if (!ctx) return
    try {
      const end = process.hrtime.bigint()
      const diffMs = Number(end - ctx.__start) / 1e6
      ctx.ms = Math.round(diffMs)
      ctx.status = reply.statusCode
      // Ta vare på respons (kort)
      let out = ''
      if (typeof payload === 'string') out = payload
      else if (payload && typeof payload === 'object') out = JSON.stringify(payload)
      if (out) ctx.res = out.length > 2000 ? out.slice(0,2000)+'…' : out
      delete ctx.__start
      pushEntry(ctx)
    } catch {}
    return payload
  })

  app.get('/v2/activity', async (req) => {
    const page = Number(req.query.page || 1)
    const pageSize = Number(req.query.pageSize || req.query.pagesize || 25)
    const start = Math.max(0, store.length - (page * pageSize))
    const end = Math.min(store.length, start + pageSize)
    const items = store.slice(start, end)
    return {
      ok: true,
      total: store.length,
      page, pageSize,
      items: items.slice().reverse() // nyeste først
    }
  })

  app.get('/v2/activity/:id', async (req, reply) => {
    const it = store.find(x => x.id === String(req.params.id))
    if (!it) { reply.code(404); return { ok:false, code:'not_found' } }
    return { ok:true, item: it }
  })

  app.delete('/v2/activity', async (req, reply) => {
    const role = String(req.headers['x-role'] || 'viewer')
    if (role !== 'admin') {
      reply.code(403); return { ok:false, code:'forbidden', title:'Admin role required' }
    }
    store.length = 0
    return { ok:true, cleared:true }
  })
}
