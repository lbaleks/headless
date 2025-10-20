#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
PLUG="$API/src/plugins"
SV="$API/src/server.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"
ORIGIN="${CORS_ORIGIN:-$(grep -E '^CORS_ORIGIN=' "$ROOT/.env" | sed -n 's/^CORS_ORIGIN=//p')}"
ORIGIN="${ORIGIN:-http://localhost:3020}"

mkdir -p "$PLUG"

# Ensure RBAC plugin exists
if [ ! -f "$PLUG/rbac.js" ]; then
  cat > "$PLUG/rbac.js" <<'JS'
const ROLES = {
  admin: { label: 'Administrator', permissions: ['*'] },
  viewer: { label: 'Viewer', permissions: ['read'] },
  sales: { label: 'Sales', permissions: ['orders:view','orders:invoice'] },
  warehouse: { label: 'Warehouse', permissions: ['msi:view','msi:update'] }
}
export default async function rbac(app) {
  app.get('/v2/auth/roles', async () => ({ ok: true, roles: ROLES }))
  app.get('/v2/auth/whoami', async (req) => {
    const roleKey = String((req.headers['x-role']||'viewer')).toLowerCase()
    const roleObj = ROLES[roleKey] ? { key: roleKey, ...ROLES[roleKey] } : { key:'viewer', ...ROLES.viewer }
    return { ok: true, role: roleObj }
  })
}
JS
fi

# Safe server.js (ESM, CORS 1x, dynamic plugins, single listen)
cat > "$SV" <<'JS'
import 'dotenv/config'
import Fastify from 'fastify'
import cors from '@fastify/cors'

const PORT = Number(process.env.PORT || 3044)
const ORIGIN = process.env.CORS_ORIGIN || 'http://localhost:3020'

const app = Fastify({ logger: true })
await app.register(cors, { origin: ORIGIN, methods: ['GET','HEAD','POST','PUT','PATCH','OPTIONS'] })

app.get('/v2/health', async () => ({
  ok: true,
  uptime: process.uptime(),
  now: new Date().toISOString(),
  env: process.env.NODE_ENV || 'development'
}))

app.get('/v2/debug/routes', async () => {
  const lines = []
  lines.push('└── (root)')
  lines.push(app.printRoutes({ includeHooks: false }))
  return lines.join('\n')
})

async function tryPlugin(name, path) {
  try {
    const mod = await import(path)
    if (mod?.default) {
      await app.register(mod.default)
      app.log.info({ plugin: name }, 'registered')
    } else {
      app.log.warn({ plugin: name }, 'no default export')
    }
  } catch (e) {
    app.log.warn({ plugin: name, err: String(e) }, 'plugin load failed (continuing)')
  }
}

await tryPlugin('feature-flags', './plugins/feature-flags.js')
await tryPlugin('magento2', './plugins/magento2.js')
await tryPlugin('creditmemos-read', './plugins/creditmemos.read.js')
await tryPlugin('invoices', './plugins/invoices.js')
await tryPlugin('credit-helper', './plugins/credit.helper.js')
await tryPlugin('msi', './plugins/msi.js')
await tryPlugin('openapi', './plugins/openapi.js')
await tryPlugin('rbac', './plugins/rbac.js')
await tryPlugin('admin-ui', './plugins/admin.ui.js')

app.listen({ port: PORT, host: '0.0.0.0' }).then(() => {
  app.log.info(`API listening on http://0.0.0.0:${PORT}`)
})
JS

# Restart cleanly
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 2.5

echo "🩺 Health:"
curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true
echo
echo "🧭 Routes:"
curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/debug/routes" || true
echo
echo "🪵 Tail log:"
tail -n 100 "$LOG" || true
