#!/usr/bin/env bash
set -euo pipefail
source ./.m2-env
source ./.m2-lib.sh
: "${PARENT_SKU:=TEST-CFG}"

SKU="${1:-}"
[ -z "$SKU" ] && { echo "Bruk: ./remove-color.sh <child-sku>"; exit 1; }

# Detach child (lar attribute option stå i fred)
set +e
OUT=$(do_write DELETE "$WRITE_BASE/configurable-products/$PARENT_SKU/children/$SKU" "")
ok=$?
set -e
if [ $ok -ne 0 ]; then
  echo "$OUT" >&2
fi

# Vis status
curl -sS -H "$AUTH_ADMIN" "$READ_BASE/configurable-products/$PARENT_SKU/children" | jq -c 'map(.sku)'
