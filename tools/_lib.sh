#!/usr/bin/env bash
set -euo pipefail

err() { printf "❌ %s\n" "$*" >&2; }

load_env() {
  local envfile=".env.local"
  [[ -f "$envfile" ]] || return 0
  while IFS= read -r raw; do
    raw="${raw%$'\r'}"
    [[ -z "$raw" || "$raw" =~ ^[[:space:]]*# ]] && continue
    [[ "$raw" =~ ^(MAGENTO_|MAGENTO_ADMIN_|MAGENTO_PREFER_ADMIN_TOKEN) ]] || continue
    key="${raw%%=*}"; val="${raw#*=}"
    if [[ "${val:0:1}" == "\"" && "${val: -1}" == "\"" ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "${val:0:1}" == "'" && "${val: -1}" == "'" ]]; then
      val="${val:1:${#val}-2}"
    fi
    export "${key}"="${val}"
  done < "$envfile"
}

compute_bases() {
  local raw="${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}"
  if [[ -z "${raw}" ]]; then
    err "MAGENTO_URL/MAGENTO_BASE_URL mangler – sett i .env.local"
    return 1
  fi
  raw="${raw%/}"
  if [[ "$raw" =~ /rest$ ]]; then
    MAGENTO_REST="$raw"
  elif [[ "$raw" =~ /rest/ ]]; then
    MAGENTO_REST="${raw%/V1}"
  else
    MAGENTO_REST="$raw/rest"
  fi
  MAGENTO_V1="$MAGENTO_REST/V1"
  export MAGENTO_REST MAGENTO_V1
}

get_admin_token() {
  local want_admin="${MAGENTO_PREFER_ADMIN_TOKEN:-1}"
  if [[ "${want_admin}" != "1" && -n "${MAGENTO_TOKEN:-}" ]]; then
    return 0
  fi
  if [[ -z "${MAGENTO_ADMIN_USERNAME:-}" || -z "${MAGENTO_ADMIN_PASSWORD:-}" ]]; then
    err "ADMIN brukernavn/passord mangler i .env.local"
    return 1
  fi
  local url="${MAGENTO_V1}/integration/admin/token"
  local resp
  resp="$(curl -sS -X POST "$url" -H 'Content-Type: application/json' \
    --data "{\"username\":\"${MAGENTO_ADMIN_USERNAME}\",\"password\":\"${MAGENTO_ADMIN_PASSWORD}\"}")" || {
      err "Admin-token request feilet"; return 1; }
  if [[ "$resp" =~ ^\".+\"$ ]]; then
    MAGENTO_TOKEN="${resp:1:${#resp}-2}"
    export MAGENTO_TOKEN
    return 0
  fi
  err "Admin-token uventet respons: ${resp}"
  return 1
}

can_write() {
  local sku="__authcheck__"
  local url="${MAGENTO_V1}/products/${sku}"
  local body='{"product":{"sku":"__authcheck__","name":"AuthCheck","attribute_set_id":4,"price":1,"status":1,"visibility":4,"type_id":"simple"}}'
  local r
  r="$(curl -sS -o /dev/null -w "%{http_code}" -X PUT "$url" \
      -H "Authorization: Bearer ${MAGENTO_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$body" || true)"
  [[ "$r" == "200" || "$r" == "201" ]]
}

get_set_and_group_ids() {
  local sku="$1"
  local prod_json
  prod_json="$(curl -sS -H "Authorization: Bearer ${MAGENTO_TOKEN}" "${MAGENTO_V1}/products/${sku}")" || return 1
  attr_set_id="$(printf "%s" "$prod_json" | sed -nE 's/.*"attribute_set_id":\s*([0-9]+).*/\1/p' | head -n1)"
  if [[ -z "$attr_set_id" ]]; then
    err "Fant ikke attribute_set_id for SKU=${sku}"; return 1
  fi
  # NB: --globoff og URL-enkodede brackets:
  local q='searchCriteria%5BfilterGroups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bfield%5D=attribute_set_id&searchCriteria%5BfilterGroups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bvalue%5D='${attr_set_id}'&searchCriteria%5BfilterGroups%5D%5B0%5D%5Bfilters%5D%5B0%5D%5Bcondition_type%5D=eq'
  local groups_json
  groups_json="$(curl -sS --globoff -H "Authorization: Bearer ${MAGENTO_TOKEN}" \
    "${MAGENTO_V1}/products/attribute-sets/groups/list?${q}")" || return 1
  group_id="$(printf "%s" "$groups_json" \
    | sed -nE 's/.*\{[^}]*"attribute_group_id":\s*([0-9]+)[^}]*"attribute_group_name":\s*"General"[^}]*\}.*/\1/p' | head -n1)"
  if [[ -z "$group_id" ]]; then
    group_id="$(printf "%s" "$groups_json" | sed -nE 's/.*"attribute_group_id":\s*([0-9]+).*/\1/p' | head -n1)"
  fi
  if [[ -z "$group_id" ]]; then
    err "Fant ikke attribute_group_id for set=${attr_set_id}"; return 1
  fi
  export attr_set_id group_id
}

ensure_attr_ibu() {
  local get_r
  get_r="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${MAGENTO_TOKEN}" \
    "${MAGENTO_V1}/products/attributes/ibu" || true)"
  [[ "$get_r" == "200" ]] && return 0
  local payload='{"attribute":{"attribute_code":"ibu","default_frontend_label":"IBU","frontend_input":"text","is_required":false,"is_unique":false,"is_user_defined":true,"frontend_labels":[{"store_id":0,"label":"IBU"}]}}'
  local create_r
  create_r="$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer ${MAGENTO_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "${MAGENTO_V1}/products/attributes" || true)"
  if [[ "$create_r" != "200" && "$create_r" != "201" ]]; then
    err "Klarte ikke å opprette attributt 'ibu' (HTTP ${create_r})"; return 1
  fi
}

assign_ibu_to_set() {
  local set_id="$1" group_id="$2"
  local payload="{\"attributeSetId\":${set_id},\"attributeGroupId\":${group_id},\"attributeCode\":\"ibu\",\"sortOrder\":10}"
  local r
  r="$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer ${MAGENTO_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "${MAGENTO_V1}/products/attribute-sets/attributes" || true)"
  [[ "$r" == "200" || "$r" == "201" || "$r" == "400" ]]
}
