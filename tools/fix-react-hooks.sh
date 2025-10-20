#!/bin/bash
set -euo pipefail

F="app/admin/products/page.tsx"
if [ ! -f "$F" ]; then
  echo "❌ Finner ikke $F – avbryter."
  exit 1
fi

echo "🔧 Retter React-hooks i $F ..."

# 1) Sørg for at filen har import for useState/useEffect
if ! grep -qE 'import\s+\{[^}]*useState' "$F"; then
  # Sett inn rett etter første import
  awk '
    NR==1 && /^import/ {print "import { useState, useEffect } from \"react\";"} 
    {print}
  ' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
fi

# 2) Bytt ut React.useState / React.useEffect med hookene direkte
perl -0777 -i -pe '
  s/\bReact\.useState\b/useState/g;
  s/\bReact\.useEffect\b/useEffect/g;
' "$F"

# 3) (Valgfritt) Fjern unødvendig `import * as React from "react";` hvis ikke lenger brukt
if grep -q 'import \* as React' "$F"; then
  if ! grep -q 'React\.' "$F"; then
    sed -i.bak '/import \* as React/d' "$F" && rm -f "$F.bak"
  fi
fi

echo "✅ Hooks fix ferdig. Starter Next.js på nytt…"
killall -9 node 2>/dev/null || true
pnpm dev