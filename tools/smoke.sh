#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${BASE:-http://localhost:3000}"

ck(){ jq -e "$1" >/dev/null 2>&1; }
fail(){ echo "❌ $*"; exit 1; }

out="$(curl -fsS "$BASE/api/debug/health" || true)"
printf '%s' "$out" | ck '.ok==true' || fail "health ikke OK"

job="$(curl -fsS -X POST "$BASE/api/jobs/run-sync" || true)"
printf '%s' "$job" | ck '.id and .counts.products>=0' || fail "run-sync feilet"

last="$(curl -fsS "$BASE/api/jobs/latest" || true)"
printf '%s' "$last" | ck '.item.id and .item.counts.products>=0' || fail "latest feilet"

echo "Smoke OK: $(printf '%s' "$job" | jq -r '.id')"
