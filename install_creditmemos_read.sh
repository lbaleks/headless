#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API_DIR="$ROOT/apps/api"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

mkdir -p "$API_DIR/src/plugins"

# Plugin: creditmemos (GET by id, search by order_id)
cat > "$API_DIR/src/plugins/magento2.creditmemos.js" <<'JS'
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
JS

# Feature flags suppler
ff="$API_DIR/src/plugins/feature-flags.js"
if [ -f "$ff" ]; then
  if ! grep -q "m2_creditmemos" "$ff"; then
    # legg til flagg idempotent: enkel sed som setter inn før siste "}" i flags
    perl -0777 -pe 's/"m2_sales_rules": true/"m2_sales_rules": true,\n      "m2_creditmemos": true/s' -i '' "$ff" || true
  fi
fi

# Patch server.js imports/registration
SV="$API_DIR/src/server.js"
if ! grep -q "magento2.creditmemos.js" "$SV"; then
  sed -i '' '1 a\
import m2CreditMemos from '"'"'./plugins/magento2.creditmemos.js'"'"'
' "$SV"
fi
grep -q "register(m2CreditMemos)" "$SV" || sed -i '' $'/await app.register(m2SalesRules)/a\\\nawait app.register(m2CreditMemos)\n' "$SV"

# Restart og smoke
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
fi
: > "$LOG"
( cd "$API_DIR" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1

echo "⚙️  Flags:"; curl -sS --max-time 5 "http://127.0.0.1:$PORT/v2/feature-flags" | jq -c . || true
echo "🔎 Creditmemo (id=4):"; curl -sS --max-time 8 "http://127.0.0.1:$PORT/v2/integrations/magento/creditmemos/4" | jq -c . || true
echo "ℹ️  List by order (order_id=1):"; curl -sS --max-time 8 "http://127.0.0.1:$PORT/v2/integrations/magento/creditmemos?order_id=1" | jq -c . || true

echo "✅ Creditmemos-read install complete."
