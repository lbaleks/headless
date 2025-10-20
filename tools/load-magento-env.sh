#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="$ROOT_DIR/.env.local"
[ -f "$ENV_FILE" ] || ENV_FILE=".env.local"
[ -f "$ENV_FILE" ] || { echo "❌ Fant ikke .env.local (søkte i $ROOT_DIR og .)"; exit 1; }

# Les kun MAGENTO_* linjer trygt
while IFS='=' read -r k v; do
  # hopp over tomme/kommenter
  [[ -z "${k// }" || "${k:0:1}" == "#" ]] && continue
  case "$k" in MAGENTO_*)
    v="${v%$'\r'}"; v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    export "$k=$v"
  esac
done < "$ENV_FILE"

# alias
: "${MAGENTO_URL:=${MAGENTO_BASE_URL:-}}"
export MAGENTO_URL

echo "✅ Lastet MAGENTO_ fra $ENV_FILE"
echo "   MAGENTO_URL=${MAGENTO_URL:-<unset>}"
echo "   Admin user: $([ -n "${MAGENTO_ADMIN_USERNAME:-}" ] && echo ja || echo nei)"
echo "   Admin pass: $([ -n "${MAGENTO_ADMIN_PASSWORD:-}" ] && echo ja || echo nei)"
echo "   Fast token: $([ -n "${MAGENTO_TOKEN:-}" ] && echo ja || echo nei)"
