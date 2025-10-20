#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-http://localhost:3000}"

say(){ printf "%s\n" "$*"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }

say "→ Starter dev bootstrap mot ${BASE}"

# 1) Sørg for at API-endepunktene finnes (idempotent patchere)
if [ -x tools/autoinstall-dev-ops.sh ]; then
  say "→ Autoinstaller (dev-ops)…"
  tools/autoinstall-dev-ops.sh || true
fi

if [ -x tools/autoinstall-akeneo-ui.sh ]; then
  say "→ Autoinstaller (Akeneo UI)…"
  tools/autoinstall-akeneo-ui.sh || true
fi

if [ -x tools/autopatch-admin-ui.sh ]; then
  say "→ Patcher admin-UI…"
  tools/autopatch-admin-ui.sh || true
fi

# 2) Seed lokale produkter (holdes separat fra Magento-data)
say "→ Seeder lokale produkter…"
curl -sS -X POST "${BASE}/api/products/seed?n=${N:-5}" | jq .

# (valgfritt) seed kunder om dev-stub finnes
say "→ (Valgfritt) seed kunder om støttet…"
curl -sS -X DELETE "${BASE}/api/customers?action=seed&n=5" | jq . || true

# 3) Kjør sync-jobb (products/customers/orders fra Magento)
say "→ Kjører sync-jobb…"
curl -sS -X POST "${BASE}/api/jobs/run-sync" | jq .

# 4) Rask sanity / totals
say "→ Totals:"
P=$(curl -sS "${BASE}/api/products?page=1&size=1" | jq -r '.total // 0')
C=$(curl -sS "${BASE}/api/customers?page=1&size=1" | jq -r '.total // 0')
O=$(curl -sS "${BASE}/api/orders?page=1&size=1"    | jq -r '.total // 0')
printf "  products: %s\n  customers: %s\n  orders:   %s\n" "$P" "$C" "$O"

# 5) Merged visning (Magento + local)
say "→ Merged products (Magento + local) – første element:"
curl -sS "${BASE}/api/products/merged?page=1&size=1" | jq '{total,first:(.items[0]//{})}'

say "✓ Bootstrap ferdig. Åpne /admin/products og /admin/customers i nettleseren."