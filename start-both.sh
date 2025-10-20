#!/usr/bin/env bash
set -euo pipefail

GATEWAY_DIR="$HOME/Documents/M2/m2-gateway"
ADMIN_DIR="$HOME/Documents/M2/admstage"

echo "➡️  Stopper tidligere prosesser…"
pkill -f "$GATEWAY_DIR/server.js" 2>/dev/null || true
pkill -f "node .*next dev -p 3000" 2>/dev/null || true

echo "➡️  Starter gateway…"
node "$GATEWAY_DIR/server.js" >/dev/null 2>&1 &

echo "➡️  Starter admin (Next.js)…"
cd "$ADMIN_DIR"
rm -rf .next
npm run dev -- -p 3000 >/dev/null 2>&1 &

sleep 1
echo
echo "✅ Kjørende:"
echo "   Gateway:  http://localhost:3044    (health: /health/magento, ACL: /ops/acl/check)"
echo "   Admin UI: http://localhost:3000/"
echo
echo "🔗 Snarveier:"
echo "   - Variant-heal:       http://localhost:3000/m2/variants"
echo "   - Link configurable:  http://localhost:3000/m2/configurable"
echo "   - Sett pris:          http://localhost:3000/m2/price"
