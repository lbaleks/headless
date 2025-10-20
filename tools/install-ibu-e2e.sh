#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/_lib.sh"

sku="${1:-}"
if [[ -z "$sku" ]]; then
  echo "Bruk: tools/install-ibu-e2e.sh <SKU>"
  exit 1
fi

load_env
compute_bases

# Skaff token om nødvendig / ønsket
if [[ -z "${MAGENTO_TOKEN:-}" || "${MAGENTO_PREFER_ADMIN_TOKEN:-1}" == "1" ]]; then
  echo "🔐 Henter admin-token…"
  get_admin_token || { err "Mangler gyldig MAGENTO_TOKEN/admin-creds"; exit 1; }
fi

echo "🔎 Base: ${MAGENTO_V1}/"

# Sjekk write
if ! can_write; then
  err "Token virker ikke for skriving (Magento_Catalog::products)."
  exit 1
fi

# Finn attribute set / group id for SKU
get_set_and_group_ids "$sku"
echo "🔹 attribute_set_id=${attr_set_id}"
echo "🔹 attribute_group_id=${group_id}"

# Sørg for at 'ibu' finnes og er assignet
echo "🛠  Oppretter/validerer attributt 'ibu'…"
ensure_attr_ibu
echo "🧩 Legger 'ibu' i set=${attr_set_id} / group=${group_id}…"
assign_ibu_to_set "$attr_set_id" "$group_id"

echo "✅ Ferdig. Du kan nå oppdatere via app-API: PATCH /api/products/update-attributes {\"sku\":\"$sku\",\"attributes\":{\"ibu\":\"37\"}}"
