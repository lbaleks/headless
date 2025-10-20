#!/usr/bin/env bash
set -euo pipefail
API_DIR="apps/api"
FF="$API_DIR/src/plugins/feature-flags.js"
mkdir -p "$API_DIR/src/plugins"

cat > "$FF" <<'JS'
export default async function featureFlagsPlugin (app) {
  app.get('/v2/feature-flags', async () => ({
    ok: true,
    flags: {
      m2_products: true,
      m2_mutations: true,
      m2_customers: true,
      m2_orders: true,
      m2_categories: true,
      m2_sales_rules: true,
      m2_creditmemos: true
    }
  }))
}
JS

PORT="${PORT:-3044}"
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
( cd "$API_DIR" && nohup npm run start > ../../.api.dev.log 2>&1 & echo $! > ../../.api.pid )
sleep 1
echo "⚙️ Flags:"
curl -sS --max-time 5 "http://127.0.0.1:$PORT/v2/feature-flags" | jq -c .
