#!/bin/bash
set -euo pipefail

echo "🔧 Patching: verify script (zsh-safe) + /api/env/check debug route"

# 1) Safer verify script for macOS/zsh (no 'unbound variable' on local vars)
cat > tools/verify-batch-2.sh <<'BASH'
#!/bin/bash
set -euo pipefail

echo "🔎 Verifiserer at batch-2 skrev filene..."

check_file() {
  local f="$1"
  if [ -f "$f" ]; then
    echo "✅ Finnes: $f"
    head -n 20 "$f" | sed 's/^/    /'
    echo
  else
    echo "❌ Mangler: $f"
    exit 1
  fi
}

check_contains() {
  local f="$1"
  local patt="$2"
  if grep -q "$patt" "$f"; then
    echo "   ↪︎ OK: Fant «$patt» i $f"
  else
    echo "   ✖ Mangel: Fant ikke «$patt» i $f"
    exit 1
  fi
}

# Produkter
check_file "app/api/products/update-attributes/route.ts"
check_contains "app/api/products/update-attributes/route.ts" "export async function PATCH"
check_contains "app/api/products/update-attributes/route.ts" "revalidateTag('products')"
check_contains "app/api/products/update-attributes/route.ts" "sku: body.sku"

check_file "app/api/products/[sku]/route.ts"
check_contains "app/api/products/[sku]/route.ts" "ctx: { params: Promise<{ sku: string }> }"
check_contains "app/api/products/[sku]/route.ts" "joinMagento"

# Kunder
check_file "app/api/customers/[id]/route.ts"
check_contains "app/api/customers/[id]/route.ts" "ctx: { params: Promise<{ id: string }> }"
check_contains "app/api/customers/[id]/route.ts" "export async function PATCH"
check_contains "app/api/customers/[id]/route.ts" "export async function PUT"

# Rydding
echo "🧹 Sjekker for .bak-filer:"
if find app -name "*.bak" | grep -q .; then
  echo "   ✖ Fant backupfiler – rydder..."
  find app -name "*.bak" -delete
else
  echo "   ✅ Ingen .bak-filer"
fi

echo
echo "🌡  Environment (shell):"
echo "   MAGENTO_URL=${MAGENTO_URL:-<unset>}"
echo "   MAGENTO_TOKEN=${MAGENTO_TOKEN:-<unset>}"

echo
echo "✅ Verifisering ferdig."
echo "➡  Start på nytt: pnpm dev"
BASH

chmod +x tools/verify-batch-2.sh

# 2) Add /api/env/check route to see env vars from Next runtime
mkdir -p app/api/env/check
cat > app/api/env/check/route.ts <<'TS'
// app/api/env/check/route.ts
import { NextResponse } from 'next/server'
export const runtime = 'nodejs'

export async function GET() {
  const u = process.env.MAGENTO_URL || ''
  const t = process.env.MAGENTO_TOKEN || ''
  // mask token for display
  const masked = t ? (t.length > 6 ? t.slice(0,3) + '...' + t.slice(-3) : '***') : '<empty>'
  return NextResponse.json({
    ok: true,
    MAGENTO_URL_present: Boolean(u),
    MAGENTO_TOKEN_present: Boolean(t),
    MAGENTO_URL_preview: u ? (u.replace(/https?:\/\//,'').slice(0,60)) : '<empty>',
    MAGENTO_TOKEN_masked: masked,
    note: 'If these are false/empty, restart dev after editing .env.local'
  })
}
TS

echo "✅ Done. Now:"
echo "1) Restart dev: pnpm dev"
echo "2) Open http://localhost:3000/api/env/check to confirm env vars are loaded."
echo "3) Use a REAL Magento SKU (not numeric id) when testing /api/products/<sku>."