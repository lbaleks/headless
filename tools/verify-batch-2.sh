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
