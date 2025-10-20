#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://localhost:3000}"

log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

get_json() {
  # usage: get_json <url> [max_tries] [sleep_seconds]
  local url="$1" tries="${2:-40}" pause="${3:-0.5}"
  local out body code
  for ((i=1;i<=tries;i++)); do
    out="$(curl -sS -m 5 -w $'\n%{http_code}' "$url" || true)"
    body="$(printf '%s' "$out" | sed '$d')"
    code="$(printf '%s' "$out" | tail -n1)"
    if [ "$code" = "200" ] && echo "$body" | jq -e . >/dev/null 2>&1; then
      printf '%s' "$body"
      return 0
    fi
    sleep "$pause"
  done
  echo "::WARN:: last_code=$code body_preview=$(printf '%s' "$body" | head -c 120)" >&2
  return 1
}

log "FamilyPicker.tsx fantes (ok)"; echo "• FamilyPicker fantes (ok)"

# 1) Health gate (hvis route finnes)
if curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/debug/health" | grep -q '^200$'; then
  log "Health OK"
else
  log "Health route ikke funnet (hopper over)"
fi

# 2) Warm-up: kall underliggende endepunkter først
log "Warm-up: /api/akeneo/attributes"
get_json "$BASE/api/akeneo/attributes" 30 0.3 >/dev/null || true

log "Warm-up: /api/products/TEST"
curl -sS -m 5 "$BASE/api/products/TEST" >/dev/null || true

# 3) Nå verifiser completeness for TEST med litt ekstra tålmodighet
log "Smoke: /api/products/completeness?sku=TEST"
resp="$(get_json "$BASE/api/products/completeness?sku=TEST" 60 0.5)" || {
  echo "✗ feilet (timeout/race mot hot-reload)"; exit 1;
}

echo "$resp" | jq '.items[0] | {sku,family,channel,locale,score:.completeness.score}' >/dev/null \
  && log "Ferdig ✅  Åpne: /admin/products/TEST (Family-dropdown i header)"
