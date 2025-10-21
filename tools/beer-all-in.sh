#!/usr/bin/env bash
set -euo pipefail

# --- Load env (.env.local) ---
ENV_FILE="$(pwd)/.env.local"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC2046
  export $(grep -E '^MAGENTO_(URL|ADMIN_USERNAME|ADMIN_PASSWORD)=' "$ENV_FILE" | xargs)
fi
: "${MAGENTO_URL:?set MAGENTO_URL in .env.local}"
: "${MAGENTO_ADMIN_USERNAME:?set MAGENTO_ADMIN_USERNAME in .env.local}"
: "${MAGENTO_ADMIN_PASSWORD:?set MAGENTO_ADMIN_PASSWORD in .env.local}"
V1="${MAGENTO_URL%/}/V1"

is_json() { jq -e . >/dev/null 2>&1; }

jwt() {
  curl -sS -X POST "$V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data "{\"username\":\"$MAGENTO_ADMIN_USERNAME\",\"password\":\"$MAGENTO_ADMIN_PASSWORD\"}" \
    | tr -d '"'
}

JWT="$(jwt)"
: "${JWT:?failed to fetch admin JWT}"

# --- Robust group finder with diagnostics ---
find_group_id() {
  local setId="$1" name="${2:-General}" url resp gid

  # A) /{setId}/groups -> array
  url="$V1/products/attribute-sets/$setId/groups"
  resp="$(curl -sS -H "Authorization: Bearer $JWT" "$url")"

  if ! is_json <<<"$resp"; then
    echo "❌ Magento groups ($url) returned non-JSON. First 200 bytes:" >&2
    printf '%s\n' "$resp" | head -c 200 | sed -e 's/[^[:print:]\t]/?/g' >&2
    gid=""
  else
    gid="$(jq -r 'if type=="array" then (map(select(.attribute_group_name|ascii_downcase=="general"))[0].attribute_group_id // empty) else empty end' 2>/dev/null <<<"$resp")"
  fi

  # B) fallback: groups/list?searchCriteria... -> {items:[...]}
  if [[ -z "${gid:-}" ]]; then
    url="$V1/products/attribute-sets/groups/list?searchCriteria%5Bfilter_groups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bfield%5D=attribute_set_id&searchCriteria%5Bfilter_groups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bvalue%5D=$setId&searchCriteria%5Bfilter_groups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bcondition_type%5D=eq"
    resp="$(curl -g -sS -H "Authorization: Bearer $JWT" "$url")"
    if ! is_json <<<"$resp"; then
      echo "❌ Magento groups/list returned non-JSON. First 200 bytes:" >&2
      printf '%s\n' "$resp" | head -c 200 | sed -e 's/[^[:print:]\t]/?/g' >&2
      gid=""
    else
      gid="$(jq -r '.items|map(select(.attribute_group_name|ascii_downcase=="general"))[0].attribute_group_id // empty' 2>/dev/null <<<"$resp")"
      [[ -n "$gid" ]] || gid="$(jq -r '.items[0].attribute_group_id // empty' 2>/dev/null <<<"$resp")"
    fi
  fi

  echo -n "${gid:-}"
}

ensure_attr() {
  local code="$1" label="$2"
  local got
  got="$(curl -sS -H "Authorization: Bearer $JWT" "$V1/products/attributes/$code" \
        | jq -r '.attribute_code // empty' 2>/dev/null || true)"
  if [[ -z "$got" ]]; then
    curl -sS -X POST "$V1/products/attributes" \
      -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
      --data "{\"attribute\":{\"attribute_code\":\"$code\",\"default_frontend_label\":\"$label\",\"frontend_input\":\"text\",\"backend_type\":\"varchar\",\"is_user_defined\":true,\"is_visible\":true,\"apply_to\":[]}}" \
      >/dev/null
  fi
}

assign_to_set() {
  local code="$1" setId="$2" groupId="$3" sort="${4:-99}"
  local resp exists
  resp="$(curl -sS -H "Authorization: Bearer $JWT" "$V1/products/attribute-sets/$setId/attributes")"
  if is_json <<<"$resp"; then
    exists="$(jq -re '.[]?|select(.attribute_code=="'"$code"'")|1' 2>/dev/null <<<"$resp" || true)"
  else
    exists=""
  fi
  if [[ "$exists" != "1" ]]; then
    curl -sS -X POST "$V1/products/attribute-sets/attributes" \
      -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
      --data "{\"attributeSetId\":$setId,\"attributeGroupId\":$groupId,\"attributeCode\":\"$code\",\"sortOrder\":$sort}" \
      >/dev/null
  fi
}

patch_app() {
  local sku="$1" kv_json="$2"
  curl -sS -X PATCH "http://localhost:3000/api/products/update-attributes" \
    -H 'Content-Type: application/json' \
    --data "{\"sku\":\"$sku\",\"attributes\":$kv_json}" >/dev/null
}

# --- Inputs ---
SKU="${1:-TEST-RED}"
IBU="${2:-42}"
SRM="${3:-12}"
HOP="${4:-75}"
MALT="${5:-55}"
SET_ID="${SET_ID:-4}"

echo "📦 Env OK. Starter…"
for code in ibu ibu2 srm hop_index malt_index; do
  case "$code" in
    ibu)         ensure_attr "$code" "IBU" ;;
    ibu2)        ensure_attr "$code" "IBU2" ;;
    srm)         ensure_attr "$code" "SRM" ;;
    hop_index)   ensure_attr "$code" "Hop Index" ;;
    malt_index)  ensure_attr "$code" "Malt Index" ;;
  esac
  echo "✓ attrib '$code' finnes"
done

GROUP_ID="$(find_group_id "$SET_ID" "General")"
if [[ -z "$GROUP_ID" ]]; then
  echo "❌ Fant ikke attribute_group_id for set=$SET_ID (se feilmeldingene over)" >&2
  exit 1
fi
echo "🔗 attribute_group_id for set=$SET_ID → $GROUP_ID"

for code in ibu ibu2 srm hop_index malt_index; do
  assign_to_set "$code" "$SET_ID" "$GROUP_ID"
done

patch_app "$SKU" "{\"ibu\":\"$IBU\",\"ibu2\":\"$IBU\",\"srm\":\"$SRM\",\"hop_index\":\"$HOP\",\"malt_index\":\"$MALT\"}"

# --- Verify views (guard if app returns HTML) ---
verify_single="$(curl -s "http://localhost:3000/api/products/$SKU")"
if is_json <<<"$verify_single"; then
  echo "$verify_single" | jq '{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2,srm:._attrs.srm,hop_index:._attrs.hop_index,malt_index:._attrs.malt_index}}'
else
  echo "⚠️  /api/products/$SKU returned non-JSON (is dev server rebuilding?)." >&2
fi

verify_merged="$(curl -s "http://localhost:3000/api/products/merged?page=1&size=200")"
if is_json <<<"$verify_merged"; then
  echo "$verify_merged" | jq '.items[]?|select(.sku=="'"$SKU"'")|{sku,ibu,srm,hop_index,malt_index,_attrs:{ibu:._attrs.ibu,ibu2:._attrs.ibu2,srm:._attrs.srm,hop_index:._attrs.hop_index,malt_index:._attrs.malt_index}}'
else
  echo "⚠️  /api/products/merged returned non-JSON." >&2
fi
