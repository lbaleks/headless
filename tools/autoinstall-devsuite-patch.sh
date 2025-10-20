#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

log "Patcher autoinstall-dev-suite med warm-up blokk"

grep -q "Warm-up" tools/autoinstall-dev-suite.sh 2>/dev/null && { log "Allerede patchet"; exit 0; }

cat >> tools/autoinstall-dev-suite.sh <<'PATCH'

# --- Warm-up etter hot reload ---
echo "→ Warm-up API-ruter"
curl -sf "$BASE/api/debug/health" >/dev/null
curl -sf "$BASE/api/akeneo/attributes" >/dev/null
curl -sf "$BASE/api/products/TEST" >/dev/null
curl -sf "$BASE/api/products/completeness?sku=TEST" >/dev/null
echo "✓ Warm-up ferdig"
PATCH

log "✅ Warm-up lagt til"
