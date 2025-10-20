#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env.local"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Fant ikke $ENV_FILE"; exit 1
fi

# Load only MAGENTO_* keys (strip quotes/CR)
eval "$(
  awk -F= '/^MAGENTO_/ && $2 {
    gsub(/\r/,"",$2); gsub(/^["'"'"']|["'"'"']$/,"",$2);
    printf("export %s=\"%s\"\n",$1,$2)
  }' "$ENV_FILE"
)"

echo "✅ Leste env fra: $ENV_FILE"
echo "   MAGENTO_URL=$MAGENTO_URL"
echo "   Admin user: $([[ -n "${MAGENTO_ADMIN_USERNAME:-}" ]] && echo ja || echo nei)"
echo "   Admin pass: $([[ -n "${MAGENTO_ADMIN_PASSWORD:-}" ]] && echo ja || echo nei)"
echo "   Fast token: $([[ -n "${MAGENTO_TOKEN:-}" ]] && echo ja || echo nei)"
