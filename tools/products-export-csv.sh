#!/usr/bin/env bash
set -euo pipefail

BASE_APP="${BASE_APP:-http://localhost:3000}"
PAGE="${PAGE:-1}"
SIZE="${SIZE:-1000}"
OUT="${1:-products-export.csv}"

command -v jq >/dev/null || { echo "jq mangler"; exit 1; }
command -v curl >/dev/null || { echo "curl mangler"; exit 1; }

echo "🔎 Henter merged produkter (page=$PAGE size=$SIZE) fra $BASE_APP ..."
json="$(curl -s -H 'Accept: application/json' \
  "$BASE_APP/api/products/merged?page=$PAGE&size=$SIZE")"

# Fail fast hvis vi har fått HTML/feil
if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
  echo "❌ Fikk ikke gyldig JSON fra appen (dev-server bygger eller feilet?)." >&2
  echo "   Prøv: curl -s -H 'Accept: application/json' $BASE_APP/api/products/merged" >&2
  exit 1
fi

echo "sku,ibu,ibu2,srm,hop_index,malt_index" > "$OUT"

jq -r '
  .items[]? |
  [
    (.sku // ""),
    (.ibu // (._attrs.ibu // "")),
    (._attrs.ibu2 // ""),
    (.srm // (._attrs.srm // "")),
    (.hop_index // (._attrs.hop_index // "")),
    (.malt_index // (._attrs.malt_index // ""))
  ] | @csv
' <<<"$json" >> "$OUT"

echo "✅ Skrev $(wc -l < "$OUT") linjer til $OUT (inkl. header)."