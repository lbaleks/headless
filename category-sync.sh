#!/usr/bin/env bash
set -euo pipefail

: "${BASE:?}"; : "${AUTH_ADMIN:?}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

FILE=""
MODE="attach"      # attach|replace
DRY_RUN=0

usage() {
  cat <<USAGE
Bruk: $0 --file <csv> [--mode attach|replace] [--dry-run]

CSV-format:
  sku,category_ids
  TEST-RED,2,4
  TEST-GREEN,"2,5,7"
  TEST-BLUE-EXTRA,2;7
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Ukjent flagg: $1"; usage; exit 1 ;;
  esac
done

[[ -n "$FILE" && -f "$FILE" ]] || { echo "❌ Fant ikke --file $FILE"; exit 1; }
[[ "$MODE" == "attach" || "$MODE" == "replace" ]] || { echo "❌ --mode må være attach|replace"; exit 1; }

curl_json() {
  curl --fail --show-error --silent -H "$AUTH_ADMIN" -H 'Content-Type: application/json' "$@"
}

echo "→ Henter eksisterende kategorier…"
EXISTING_IDS_JSON="$(curl_json "$READ_BASE/categories" | jq -c '.. | objects | .id? | select(.!=null)')"
# Gjør om til unik, sortert int-liste
EXISTING_IDS="$(printf '%s\n' "$EXISTING_IDS_JSON" | jq -cs 'map(tonumber) | unique')"

# Hjelper: parse category_ids-feltet til array<int> og valider mot eksisterende
parse_and_validate_ids() {
  local raw="$1"
  # Fjern inline-kommentar etter #, trim
  raw="${raw%%#*}"
  raw="$(printf '%s' "$raw" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [[ -n "$raw" ]] || { echo "[]"; return 0; }

  # Bytt semikolon til komma, split på komma, trim, filtrer tall
  local arr
  arr="$(printf '%s' "$raw" | tr ';' ',' | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))')" || arr="[]"

  # behold bare heltall
  local ints
  ints="$(printf '%s' "$arr" | jq '[ .[] | select(test("^[0-9]+$")) | tonumber ]')" || ints="[]"

  # valider mot eksisterende
  local validated
  validated="$(jq -nc --argjson want "$ints" --argjson have "$EXISTING_IDS" '[ $want[] | select( . as $id | ($have|index($id)) != null ) ]')" || validated="[]"
  echo "$validated"
}

# Les CSV
# Tillat header (hopper over første linje hvis den starter med "sku")
first=1
while IFS= read -r line || [[ -n "$line" ]]; do
  # hopp over blanke/kommentar-linjer
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "${line:0:1}" == "#" ]] && continue
  if (( first )); then
    first=0
    if [[ "$line" =~ ^[[:space:]]*sku[[:space:]]*, ]]; then
      continue
    fi
  fi

  # Grov CSV-splitt: første felt = sku, resten = category_ids (kan være med komma/semikolon)
  sku="${line%%,*}"
  rest="${line#*,}"

  # trim sku
  sku="$(printf '%s' "$sku" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [[ -n "$sku" ]] || continue

  target_ids="$(parse_and_validate_ids "$rest")"
  # hent nåværende category_links → int-liste
  curr_ids="$(curl_json "$READ_BASE/products/$sku?fields=extension_attributes" \
            | jq -c '(.extension_attributes.category_links // []) | map(.category_id|tonumber) | unique')" || curr_ids="[]"

  # beregn ny liste
  if [[ "$MODE" == "attach" ]]; then
    new_ids="$(jq -nc --argjson a "$curr_ids" --argjson b "$target_ids" '( + )| unique | map(tonumber) | unique)')"
  else
    new_ids="$target_ids"
  fi

  # tidlig exit hvis identisk
  same="$(jq -nc --argjson a "$curr_ids" --argjson b "$new_ids" '($a|sort)==($b|sort)')"
  [[ "$same" == "true" ]] && { echo "[$sku] $MODE: uendret $(printf '%s' "$curr_ids")"; continue; }

  echo "[$sku] $MODE: $(printf '%s' "$curr_ids")  ->  $(printf '%s' "$new_ids")"

  # bygg payload med category_links (Magento vil ha strings)
  payload="$(jq -nc --arg sku "$sku" --argjson ids "$new_ids" \
    '{product:{sku:$sku,extension_attributes:{category_links: ($ids|map({position:0,category_id:(tostring)}))}}}')"

  if (( DRY_RUN )); then
    echo "DRY-RUN: would PUT $sku => $(printf '%s' "$new_ids")"
    continue
  fi

  curl_json -X PUT --data-binary "$payload" "$WRITE_BASE/products/$sku" >/dev/null \
    && echo "✅ $sku oppdatert" \
    || echo "❌ $sku feilet (se over)"
done < "$FILE"