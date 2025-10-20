#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/src/lib/magento.ts"

if [ ! -f "$FILE" ]; then
  echo "Finner ikke $FILE – har du kjørt install-magento-auth tidligere?" >&2
  exit 1
fi

echo "→ Patcher src/lib/magento.ts til å foretrekke admin-login…"
tmp="$(mktemp)"
awk '
  BEGIN{userLine=passLine=baseLine=0}
  /const USER *=/{userLine=NR}
  /const PASS *=/{passLine=NR}
  /let cachedToken: string \| null =/{cacheLine=NR}
  {print}
' "$FILE" > "$tmp"

# Bytt ut cachedToken-init slik at den blir null hvis USER/PASS finnes (tving admin-login)
perl -0777 -i -pe '
  s/let\s+cachedToken:\s*string\s*\|\s*null\s*=\s*([\s\S]*?)\n\n/let cachedToken: string | null = (process.env.MAGENTO_ADMIN_USERNAME || process.env.M2_ADMIN_USERNAME) && (process.env.MAGENTO_ADMIN_PASSWORD || process.env.M2_ADMIN_PASSWORD)\n  ? null\n  : (process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || process.env.M2_TOKEN || null)\n\n/s;
' "$FILE"

# Legg inn en eksplisitt preferanse-flag (kan settes i .env.local ved behov)
if ! grep -q 'PREFER_ADMIN_LOGIN' "$FILE"; then
  perl -0777 -i -pe '
    s/(const USER[\s\S]*?;\nconst PASS[\s\S]*?;\n)/$1\nconst PREFER_ADMIN_LOGIN = (process.env.MAGENTO_PREFER_ADMIN_LOGIN === "1" || process.env.MAGENTO_PREFER_ADMIN_LOGIN === "true");\n/s;
  ' "$FILE"
  perl -0777 -i -pe '
    s/if\s*\(!__isServer\)[\s\S]*?;\n  if\s*\(!BASE\)[\s\S]*?;\n\n  if\s*\(cachedToken\)\s*return\s*cachedToken;/if (!__isServer) throw new Error('"'"'Magento client used on client'"'"');\n  if (!BASE) throw new Error('"'"'Missing MAGENTO_BASE_URL \/ M2_BASE_URL \/ NEXT_PUBLIC_GATEWAY_BASE'"'"');\n\n  if (cachedToken && !PREFER_ADMIN_LOGIN) return cachedToken;/s;
  ' "$FILE"
fi

echo "→ Rydder cache…"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true
echo "✓ Ferdig. Start dev på nytt og test /api/_debug/ping."
