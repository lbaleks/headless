#!/usr/bin/env bash
set -euo pipefail

echo "🛠 Fikser duplisert NOW og Next 15 params i route..."

# --- 1) Fix dupliserte/feile NOW i kundedetalj-siden ---
CUST="app/admin/customers/[id]/page.tsx"
if [ -f "$CUST" ]; then
  # a) Bytt alle 'const NOW = NOW;' til korrekt Date.now()
  perl -0777 -i -pe 's/^\s*const\s+NOW\s*=\s*NOW\s*;\s*$/const NOW = Date.now();/mg' "$CUST"
  # b) Behold kun første forekomst av "const NOW = Date.now();"
  perl -0777 -i -pe 'my $c=0; s/^\s*const NOW = Date\.now\(\);\s*\n/($c++ ? "" : $&)/meg' "$CUST"
fi

# --- 2) Next 15: ctx.params må awaites i /api/products/[sku] ---
ROUTE="app/api/products/[sku]/route.ts"
if [ -f "$ROUTE" ]; then
  # a) Oppdater typesignaturen til Promise<{ sku: string }>
  perl -0777 -i -pe 's/\{\s*params\s*:\s*\{\s*sku\s*:\s*string\s*\}\s*\}/\{ params: Promise<{ sku: string }> \}/g' "$ROUTE"

  # b) Bytt const sku = ctx?.params?.sku / ctx.params.sku -> await ctx.params
  perl -0777 -i -pe 's/const\s+sku\s*=\s*ctx\??\.params\??\.sku\s*;/const { sku } = await ctx.params;/g' "$ROUTE"

  # c) Hvis funksjonen ikke er async, gjør den async (sikkerhetsnett)
  perl -0777 -i -pe 's/\bexport\s+function\s+GET\b/export async function GET/g' "$ROUTE"
fi

echo "✅ Fikser ferdig. Starter dev på nytt..."
pkill -9 node 2>/dev/null || true
pnpm dev
