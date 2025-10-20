#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.."; pwd)"
FILE="$ROOT/app/api/orders/route.ts"

if [ ! -f "$FILE" ]; then
  echo "⚠️  Fil ikke funnet: $FILE"
  exit 1
fi

echo "→ Fjerner duplikat av 'import { NextResponse } from \"next/server\"' i $FILE …"

# Fjern ALLE forekomster etter første
awk '
/import { NextResponse } from '\''next\/server'\''/ {
  if (seen) next
  seen=1
}
{ print }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

echo "→ Rydder .next cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

echo "✓ Ferdig! Kjør: npm run dev"