#!/usr/bin/env bash
set -euo pipefail
: "${BASE_APP:=http://localhost:3000}"
source "$HOME/Documents/M2/tools/beer-qol.sh"
sku="${1:?usage: appset-cli.sh <SKU> [ibu] [ibu2] [srm] [hop] [malt]}"
shift || true
appset "$sku" "$@"
