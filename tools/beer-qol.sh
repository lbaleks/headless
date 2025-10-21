#!/usr/bin/env bash

# --- robust env bootstrap ----------------------------------------------------
ROOT="${ROOT:-$HOME/Documents/M2}"
ENVF="$ROOT/.env.local"
BASE_APP="${BASE_APP:-http://localhost:3000}"

# Last .env.local om variabler mangler
need_env=0
[[ -z "${MAGENTO_URL:-}" ]] && need_env=1
[[ -z "${MAGENTO_ADMIN_USERNAME:-}" || -z "${MAGENTO_ADMIN_PASSWORD:-}" ]] && need_env=1
if [[ "$need_env" == "1" && -f "$ENVF" ]]; then
  set -a; source "$ENVF"; set +a
fi

# Sanity
if [[ -z "${MAGENTO_URL:-}" ]]; then
  echo "⚠️  MAGENTO_URL mangler. Legg den i $ENVF"; return 1 2>/dev/null || exit 1
fi

V1="${MAGENTO_URL%/}/V1"

# --- helpers -----------------------------------------------------------------
admin_jwt() {
  # Auto-load env om nødvendig
  if [[ -z "${MAGENTO_ADMIN_USERNAME:-}" || -z "${MAGENTO_ADMIN_PASSWORD:-}" ]]; then
    if [[ -f "$ENVF" ]]; then set -a; source "$ENVF"; set +a; fi
  fi
  if [[ -z "${MAGENTO_ADMIN_USERNAME:-}" || -z "${MAGENTO_ADMIN_PASSWORD:-}" ]]; then
    echo "❌ MAGENTO_ADMIN_USERNAME/PASSWORD mangler i miljøet (og/eller i $ENVF)" >&2
    return 1
  fi
  curl -sS -X POST "$V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data '{"username":"'"$MAGENTO_ADMIN_USERNAME"'","password":"'"$MAGENTO_ADMIN_PASSWORD"'"}' \
  | tr -d '"'
}

# Liten wrapper som krever JSON, og gir tydelig feilmld hvis ikke
_http_json() {
  # $1=url
  local url="$1"
  local out
  out="$(curl -sS -H 'Accept: application/json' "$url")" || { echo "⚠️  $url -> curl feilet" >&2; return 2; }
  # prøv å parse; hvis det feiler, vis begynnelsen av svaret
  if ! jq -e . >/dev/null 2>&1 <<<"$out"; then
    echo "⚠️  $url returnerte ikke JSON (dev-server bygger? status 500?)." >&2
    printf '%s\n' "$out" | head -n 20 >&2
    return 3
  fi
  printf '%s' "$out"
}

appget() {
  local sku="${1:?bruk: appget <SKU>}"
  _http_json "$BASE_APP/api/products/$sku" \
    | jq '{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2,srm:._attrs.srm,hop_index:._attrs.hop_index,malt_index:._attrs.malt_index}}'
  _http_json "$BASE_APP/api/products/merged?page=1&size=200" \
    | jq --arg sku "$sku" '.items[]?|select(.sku==$sku)|{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2,srm:._attrs.srm,hop_index:._attrs.hop_index,malt_index:._attrs.malt_index}}'
}

mageget() {
  local sku="${1:?bruk: mageget <SKU>}"
  local jwt; jwt="$(admin_jwt)" || return 1
  curl -g -sS -H "Authorization: Bearer $jwt" \
    "$V1/products/$sku?storeId=0&fields=sku,custom_attributes%5Battribute_code%2Cvalue%5D" \
  | jq '.custom_attributes[]?|select(.attribute_code|IN("ibu","ibu2","srm","hop_index","malt_index"))'
}

appset() {
  local sku="${1:?bruk: appset <SKU> [ibu] [ibu2] [srm] [hop_index] [malt_index]}"
  local _ibu="${2:-}" _ibu2="${3:-}" _srm="${4:-}" _hop="${5:-}" _malt="${6:-}"
  local payload='{"sku":"'"$sku"'","attributes":{}}'
  [[ -n "$_ibu"  ]] && payload="$(jq --arg v "$_ibu"  '.attributes.ibu=$v'        <<<"$payload")"
  [[ -n "$_ibu2" ]] && payload="$(jq --arg v "$_ibu2" '.attributes.ibu2=$v'       <<<"$payload")"
  [[ -n "$_srm"  ]] && payload="$(jq --arg v "$_srm"  '.attributes.srm=$v'        <<<"$payload")"
  [[ -n "$_hop"  ]] && payload="$(jq --arg v "$_hop"  '.attributes.hop_index=$v'  <<<"$payload")"
  [[ -n "$_malt" ]] && payload="$(jq --arg v "$_malt" '.attributes.malt_index=$v' <<<"$payload")"

  curl -sS -X PATCH "$BASE_APP/api/products/update-attributes" \
    -H 'Accept: application/json' -H 'Content-Type: application/json' \
    -d "$payload" | jq '.success // .'
}

beer-smoke() {
  local sku="${1:?bruk: beer-smoke <SKU>}"
  echo "✍️  write via app (noop if same values)…"
  appset "$sku" 42 42 12 75 55 >/dev/null || true

  echo "🔎 app (single)"
  _http_json "$BASE_APP/api/products/$sku" \
    | jq '{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2}}'

  echo "🔎 magento (jwt)"
  mageget "$sku" || true
}

echo "Loaded helpers:

  appget <SKU>           # les fra app (single + merged)
  mageget <SKU>          # les direkte fra Magento (admin JWT)
  appset <SKU> [ibu] [ibu2] [srm] [hop_index] [malt_index]
  beer-smoke <SKU>       # liten sanity: write + read

Kjør:  source tools/beer-qol.sh
eller: tools/beer-qol.sh <command> …"
