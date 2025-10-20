#!/usr/bin/env bash
set -euo pipefail

: "${BASE:?}"; : "${AUTH_ADMIN:?}"
READ_BASE="${READ_BASE:-$BASE/rest/all/V1}"
WRITE_BASE="${WRITE_BASE:-$BASE/rest/V1}"

FILE=""
MODE="attach"   # or replace
DRY_RUN=0

# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)  FILE="${2:-}"; shift 2;;
    --mode)  MODE="${2:-}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

[[ -n "$FILE" && -f "$FILE" ]] || { echo "❌ Mangler --file <csv>"; exit 1; }
[[ "$MODE" == "attach" || "$MODE" == "replace" ]] || { echo "❌ --mode attach|replace"; exit 1; }

curl_json() {
  curl --fail --show-error --silent \
    -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
    "$@"
}

# --- fetch existing category ids (numbers) ---
echo "→ Henter eksisterende kategorier…"
EXISTING_IDS=$(
  curl_json "$READ_BASE/categories" \
  | jq -c '.. | objects | .id? | select(.!=null)' \
  | jq -cs 'map(tonumber) | unique'
)

# --- helpers ---
trim() { sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
parse_and_validate_ids() {
  # input: raw list string (e.g. "2,4" or "2;7")
  local raw="$1"
  local arr ints validated
  raw="$(printf %s "$raw" | trim)"
  [[ -n "$raw" ]] || { echo "[]"; return; }
  arr="$(printf %s "$raw" | tr ';' ',' | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))')"
  ints="$(printf %s "$arr" | jq '[ .[] | select(test("^[0-9]+$")) | tonumber ]')"
  validated="$(jq -nc --argjson want "$ints" --argjson have "$EXISTING_IDS" \
    '[ $want[] | select( . as $id | ($have|index($id)) != null ) ]')"
  echo "$validated"
}

merge_attach() {
  # $1 current json arr, $2 target json arr  -> union numeric unique
  jq -nc --argjson a "$1" --argjson b "$2" '($a + $b) | unique | map(tonumber) | unique'
}

same_set() {
  # $1, $2 json arrays -> boolean equal as sets
  jq -nc --argjson a "$1" --argjson b "$2" '($a|sort)==($b|sort)'
}

# --- process CSV ---
first=1
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "${line:0:1}" == "#" ]] && continue

  if (( first )); then
    first=0
    [[ "$line" =~ ^[[:space:]]*sku[[:space:]]*, ]] && continue
  fi

  # split "sku,category_ids" (category_ids can contain commas/semicolons)
  sku="$(printf %s "$line" | awk -F',' '{print $1}' | trim)"
  rest="$(printf %s "$line" | sed -E 's/^[^,]+,//')"
  [[ -n "$sku" ]] || continue

  target_ids="$(parse_and_validate_ids "$rest")"
  # read current ids
  curr_ids="$(
    curl_json "$READ_BASE/products/$sku?fields=extension_attributes" \
    | jq -c '(.extension_attributes.category_links // []) | map(.category_id|tonumber) | unique'
  )"

  if [[ "$MODE" == "attach" ]]; then
    new_ids="$(merge_attach "$curr_ids" "$target_ids")"
  else
    new_ids="$target_ids"
  fi

  if [[ "$(same_set "$curr_ids" "$new_ids")" == "true" ]]; then
    echo "[$sku] $MODE: uendret $(printf %s "$curr_ids")"
    continue
  fi

  echo "[$sku] $MODE: $(printf %s "$curr_ids")  ->  $(printf %s "$new_ids")"

  payload="$(jq -nc --argjson ids "$new_ids" \
    '{product:{extension_attributes:{category_links:($ids|map({position:0,category_id:(.|tostring)}))}}}')"

  if (( DRY_RUN )); then
    echo "DRY-RUN: would PUT $sku => $(printf %s "$new_ids")"
    continue
  fi

  curl_json -X PUT --data-binary "$payload" "$WRITE_BASE/products/$sku" >/dev/null \
    && echo "✅ $sku oppdatert" \
    || echo "❌ $sku feilet"
done < "$FILE"
