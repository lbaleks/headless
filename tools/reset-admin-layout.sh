#!/usr/bin/env bash
set -euo pipefail

FILE="app/admin/layout.tsx"
mkdir -p "$(dirname "$FILE")"

# Write a minimal, correct layout that uses the named export AdminShell
cat > "$FILE" <<'TSX'
import React from 'react'
import { AdminShell } from '@/src/components/AdminShell'

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return <AdminShell>{children}</AdminShell>
}
TSX

echo "✓ Skrev $FILE"

# Sanity check: do we actually have AdminShell as a named export?
if [[ ! -f "src/components/AdminShell.tsx" && ! -f "src/components/AdminShell.ts" ]]; then
  echo "⚠️  Fant ikke src/components/AdminShell.tsx/ts. Sjekk filsti og navn."
else
  if ! grep -q "export .*AdminShell" src/components/AdminShell.tsx 2>/dev/null && \
     ! grep -q "export .*AdminShell" src/components/AdminShell.ts 2>/dev/null ; then
    echo "⚠️  'AdminShell' ser ikke ut til å være eksportert som named export."
    echo "    Sørg for at filen inneholder f.eks.: export function AdminShell(...) { ... }"
  fi
fi

echo "→ Rydder .next…"
rm -rf .next .next/cache 2>/dev/null || true
echo "✓ Ferdig. Start dev-server på nytt: npm run dev"
