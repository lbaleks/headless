#!/usr/bin/env bash
set -euo pipefail

API="apps/api"
SV="$API/src/server.js"
LOG=".api.dev.log"
PIDF=".api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"
ORIGIN="$(grep -E '^CORS_ORIGIN=' .env | sed -n 's/^CORS_ORIGIN=//p')"
ORIGIN="${ORIGIN:-http://localhost:3020}"

mkdir -p "$API/src/plugins"

cat > "$SV" <<JS
import "./env-load.js"
import Fastify from "fastify"
import cors from "@fastify/cors"

// core/debug
import featureFlags from "./plugins/feature-flags.js"

// M2 domains
import magento2 from "./plugins/magento2.js"
import m2Customers from "./plugins/magento2.customers.js"
import m2Orders from "./plugins/magento2.orders.js"
import m2Categories from "./plugins/magento2.categories.js"
import m2SalesRules from "./plugins/magento2.salesrules.js"
import m2CreditMemos from "./plugins/magento2.creditmemos.js"
import m2Invoices from "./plugins/magento2.invoices.js"

// RBAC + Docs
import rbac from "./plugins/auth.rbac.js"
import openapi from "./plugins/openapi.js"

const PORT = Number(process.env.PORT || ${PORT})
const ORIGIN = process.env.CORS_ORIGIN || "${ORIGIN}"

const app = Fastify({ logger: true })

// CORS én gang
await app.register(cors, { origin: ORIGIN, methods: ["GET","HEAD","POST","PUT","PATCH","OPTIONS"] })

// Health
app.get("/v2/health", async () => ({
  ok: true,
  uptime: process.uptime(),
  now: new Date().toISOString(),
  env: process.env.NODE_ENV || "development"
}))

// Routes tree (tekst)
app.get("/v2/debug/routes", async () => {
  const lines = []
  lines.push("└── (root)")
  lines.push(app.printRoutes({ includeHooks: false }))
  return lines.join("\\n")
})

// Plugins – rekkefølge
await app.register(featureFlags)
await app.register(rbac)
await app.register(magento2)
await app.register(m2Customers)
await app.register(m2Orders)
await app.register(m2Categories)
await app.register(m2SalesRules)
await app.register(m2CreditMemos)
await app.register(m2Invoices)
await app.register(openapi)

// Lytt KUN én gang
app.listen({ port: PORT, host: "0.0.0.0" }).then(() => {
  app.log.info(\`API listening on http://0.0.0.0:\${PORT}\`)
})
JS

# safe restart
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
fi
: > "$LOG"
( cd "$API" && nohup npm run start > "../$LOG" 2>&1 & echo $! > "../$PIDF" )
sleep 1

echo "🩺 Health:";        curl -sS --max-time 5 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true
echo "🧭 Routes:";        curl -sS --max-time 5 "http://127.0.0.1:$PORT/v2/debug/routes" | sed -n '1,80p' || true
echo "🔑 Whoami:";        curl -sS --max-time 5 -H 'x-api-key: dev-admin-key' "http://127.0.0.1:$PORT/v2/auth/whoami" | jq -c . || true
echo "📜 OpenAPI:";       curl -sS --max-time 5 "http://127.0.0.1:$PORT/v2/openapi.json" | jq -c '.info.version' || true
echo "✅ Server reparert."
