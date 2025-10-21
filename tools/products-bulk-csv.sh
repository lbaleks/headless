#!/usr/bin/env bash
set -euo pipefail

BASE_APP="${BASE_APP:-http://localhost:3000}"
CSV="${1:?bruk: tools/products-bulk-csv.sh <fil.csv>}"
DRY="${DRY_RUN:-0}"

command -v jq >/dev/null || { echo "jq mangler"; exit 1; }
command -v curl >/dev/null || { echo "curl mangler"; exit 1; }

echo "📥 Leser: $CSV"
[ -f "$CSV" ] || { echo "Fant ikke $CSV"; exit 1; }

total=0; ok=0; fail=0; skipped=0

# Viktig: IKKE pipe inn i while (ellers subshell og tellere blir 0).
# Håndter CRLF og tomme linjer.
# Forventer header: sku,ibu,ibu2,srm,hop_index,malt_index
{
  read -r _header || true   # dropp header
  while IFS=, read -r sku ibu ibu2 srm hop hopmalt; do
    # Trim CR/LF og anførselstegn
    for v in sku ibu ibu2 srm hop hopmalt; do
      val="${!v}"
      val="${val%$'\r'}"
      val="${val%\"}"; val="${val#\"}"
      printf -v "$v" '%s' "$val"
    done

    # Hopp over helt tomme linjer
    if [[ -z "$sku$ibu$ibu2$srm$hop$hopmalt" ]]; then
      continue
    fi

    total=$((total+1))

    payload='{"sku":"'"$sku"'","attributes":{}}'
    [[ -n "$ibu"     ]] && payload="$(jq --arg v "$ibu"     '.attributes.ibu=$v'      <<<"$payload")"
    [[ -n "$ibu2"    ]] && payload="$(jq --arg v "$ibu2"    '.attributes.ibu2=$v'     <<<"$payload")"
    [[ -n "$srm"     ]] && payload="$(jq --arg v "$srm"     '.attributes.srm=$v'      <<<"$payload")"
    [[ -n "$hop"     ]] && payload="$(jq --arg v "$hop"     '.attributes.hop_index=$v'<<<"$payload")"
    [[ -n "$hopmalt" ]] && payload="$(jq --arg v "$hopmalt" '.attributes.malt_index=$v'<<<"$payload")"

    has_any="$(jq -r '.attributes | length' <<<"$payload")"
    if [[ "$has_any" == "0" ]]; then
      echo "↪️  $sku: ingen attribs – hopper"
      skipped=$((skipped+1))
      continue
    fi

    if [[ "$DRY" == "1" ]]; then
      echo "🧪 (dry-run) $sku ← $(jq -c '.attributes' <<<"$payload")"
      ok=$((ok+1))
      continue
    fi

    # To forsøk for å være snill mot dev-server
    for attempt in 1 2; do
      resp="$(curl -s -X PATCH "$BASE_APP/api/products/update-attributes" \
        -H 'Accept: application/json' -H 'Content-Type: application/json' \
        -d "$payload")"
      if [[ "$(jq -r '.success // empty' <<<"$resp" 2>/dev/null)" == "true" ]]; then
        echo "✅ $sku"
        ok=$((ok+1))
        break
      fi
      if [[ "$attempt" == "2" ]]; then
        echo "❌ $sku (response: $(jq -c . <<<"$resp" 2>/dev/null || echo "$resp"))"
        fail=$((fail+1))
      else
        echo "… retry $sku"
        sleep 0.3
      fi
    done
  done
} < "$CSV"

echo "———"
echo "📊 Ferdig. Totalt: $total  OK: $ok  Feilet: $fail  Skippet: $skipped"
exit 0