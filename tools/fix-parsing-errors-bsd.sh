#!/bin/bash
set -euo pipefail

echo "🧹 Fikser vanlige parsing-feil…"

# 1) Sørg for semikolon etter 'use client' / 'use server' i .ts/.tsx
#    (BSD-sed takler ikke \n lett, så vi bruker perl uten lookbehind)
while IFS= read -r -d '' f; do
  perl -0777 -i -pe "s/('use (?:client|server)')\s*\n/\$1;\n/s" "$f"
done < <(find . -type f \( -name "*.ts" -o -name "*.tsx" \) -print0)

# 2) Rydd opp i mulige doble 'use client' uten semikolon (edge-cases)
while IFS= read -r -d '' f; do
  perl -0777 -i -pe "s/('use (?:client|server)')\s*('use (?:client|server)')/\$1;\n\$2/sg" "$f"
done < <(find . -type f \( -name "*.ts" -o -name "*.tsx" \) -print0)

# 3) Skriv et trygt middleware.ts (Next 13/14 kompatibelt)
cat > middleware.ts <<'MID'
import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

export function middleware(_req: NextRequest) {
  // Legg inn auth / rewrites her ved behov
  return NextResponse.next();
}

export const config = {
  // Tillat statiske assets; alt annet matcher.
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\..*).*)'],
};
MID

echo "✅ Parsing-fixes gjort. Kjører eslint --fix…"
pnpm run lint --fix || true
