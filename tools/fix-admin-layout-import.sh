#!/usr/bin/env bash
set -euo pipefail

FILE="app/admin/layout.tsx"

if [ ! -f "$FILE" ]; then
  echo "Finner ikke $FILE"; exit 1
fi

# Fjern evt. feil default-import av AdminShell
perl -0777 -pe "s/import\s+AdminShell\s+from\s+['\"]@\/src\/components\/AdminShell['\"];?\n?//g" -i "$FILE"

# Legg til korrekt named import hvis den ikke finnes
if ! grep -q "import { AdminShell } from '@/src/components/AdminShell'" "$FILE"; then
  # Sett inn øverst etter 'use client' eller første import
  if grep -q "^'use client';" "$FILE"; then
    perl -0777 -pe "s/^'use client';\n/'use client';\nimport { AdminShell } from '@\/src\/components\/AdminShell';\n/s" -i "$FILE"
  else
    perl -0777 -pe "s/^import /import { AdminShell } from '@\/src\/components\/AdminShell';\nimport /s" -i "$FILE"
  fi
fi

echo "✓ Import i $FILE er satt til: import { AdminShell } from '@/src/components/AdminShell'"
echo "→ Rydder .next-cache…"
rm -rf .next
echo "✓ Ferdig. Start på nytt: npm run dev"
