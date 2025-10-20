#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
run(){ local s="$1"; shift || true; if [ -x "$s" ]; then log "→ $s"; "$s" "$@"; else log "→ Skipper $s (finnes ikke)"; fi; }

log "Starter DEV-suite autoinstaller…"

# 0) Sikre runtime-mapper
mkdir -p var/{audit,jobs,locks,attributes}
log "✓ Runtime-mapper OK"

# 1) Health + base autoinstall (du har begge)
run tools/autoinstall-health.sh
run tools/autoinstall-all.sh

# 2) Akeneo grunnsteg
run tools/autoinstall-akeneo.sh             # families/channels + completeness-kobling
run tools/autoinstall-akeneo-v2.sh || true  # attributes + family rules (tåler at du har kjørt manuelt)

# 3) Completeness (API + UI + channels/locale)
run tools/autoinstall-completeness.sh
run tools/autoinstall-completeness-ui.sh
run tools/autoinstall-channels.sh

# 4) CSV import/export + UI-knapper
run tools/autoinstall-csv.sh

# 5) Product detail extras (family dropdown + mini sync)
run tools/autoinstall-family-detail.sh
run tools/autoinstall-syncnow-detail.sh

# 6) Røyk-test (API)
if BASE=${BASE:-http://localhost:3000} bash tools/smoke.sh >/dev/null 2>&1; then
  BASE=${BASE:-http://localhost:3000} bash tools/smoke.sh
else
  log "⚠ smoke.sh ikke funnet – hopper over"
fi

# 7) Mini verifisering – completeness på TEST
if curl -fsS 'http://localhost:3000/api/products/completeness?sku=TEST' | jq -e '.items[0].completeness.score' >/dev/null; then
  SCORE=$(curl -fsS 'http://localhost:3000/api/products/completeness?sku=TEST' | jq '.items[0].completeness.score')
  log "✓ Completeness(TEST) = $SCORE"
else
  log "⚠ Completeness-sjekk hoppet over (endpoint ikke tilgjengelig?)"
fi

log "Ferdig ✅  Åpne /admin/products og /admin/completeness"

# --- Warm-up etter hot reload ---
echo "→ Warm-up API-ruter"
curl -sf "$BASE/api/debug/health" >/dev/null
curl -sf "$BASE/api/akeneo/attributes" >/dev/null
curl -sf "$BASE/api/products/TEST" >/dev/null
curl -sf "$BASE/api/products/completeness?sku=TEST" >/dev/null
echo "✓ Warm-up ferdig"
