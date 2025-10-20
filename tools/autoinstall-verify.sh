#!/usr/bin/env bash
set -Eeuo pipefail
. tools/_lib.sh
BASE="${BASE:-http://localhost:3000}"
log "→ Verifiserer…"
curl -fsS "$BASE/api/debug/health" | jq . >/dev/null || { log "health feilet"; exit 1; }
curl -fsS -X POST "$BASE/api/jobs/run-sync" | jq '.id,.counts' >/dev/null
curl -fsS "$BASE/api/jobs/latest" | jq '.item.id,.item.counts' >/dev/null
log "✓ OK"

# — Completeness-verifisering —
echo "→ Completeness"
bash tools/verify-completeness.sh >/dev/null
[ $? -eq 0 ] && echo "   ✓ completeness OK"
