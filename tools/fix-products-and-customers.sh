#!/usr/bin/env bash
set -euo pipefail

echo "🛠 Fixing customers NOW, product [sku] params, and revalidation…"

# ---------- 1) Customer detail: keep ONE const NOW = Date.now(); ----------
CUST="app/admin/customers/[id]/page.tsx"
if [ -f "$CUST" ]; then
  # a) Replace any 'const NOW = NOW;' lines with correct Date.now()
  perl -0777 -i -pe 's/^\s*const\s+NOW\s*=\s*NOW\s*;\s*$/const NOW = Date.now();/mg' "$CUST"
  # b) Keep only the first 'const NOW = Date.now();'
  perl -0777 -i -pe 'my $c=0; s/^\s*const NOW = Date\.now\(\);\s*\n/($c++ ? "" : $&)/meg' "$CUST"
fi

# ---------- 2) Next 15 route handler params for /api/products/[sku] ----------
ROUTE="app/api/products/[sku]/route.ts"
if [ -f "$ROUTE" ]; then
  # a) Ensure function is async
  perl -0777 -i -pe 's/\bexport\s+function\s+GET\b/export async function GET/g' "$ROUTE"
  # b) Signature: params is a Promise<{ sku: string }>
  perl -0777 -i -pe 's/\{\s*params\s*:\s*\{\s*sku\s*:\s*string\s*\}\s*\}/\{ params: Promise<{ sku: string }> \}/g' "$ROUTE"
  # c) Always await ctx.params (and destructure)
  perl -0777 -i -pe 's/const\s+sku\s*=\s*ctx\??\.params\??\.sku\s*;?/const { sku } = await ctx.params;/g' "$ROUTE"
fi

# ---------- 3) Revalidate list after PATCH so overview updates ----------
UPD="app/api/products/update-attributes/route.ts"
if [ -f "$UPD" ]; then
  # a) Import revalidateTag (idempotent)
  if ! grep -q "from 'next/cache'" "$UPD"; then
    # insert after first import
    awk 'NR==1{print "import { revalidateTag } from '\047next/cache\047'"}{print}' "$UPD" > "$UPD.tmp" && mv "$UPD.tmp" "$UPD"
  fi

  # b) After successful write, call revalidateTag('products')
  #    This only inserts if not already present.
  if ! grep -q "revalidateTag('products')" "$UPD"; then
    perl -0777 -i -pe 's/(return\s+NextResponse\.json\(\s*\{\s*ok\s*:\s*true[^)]*\)\s*\)\s*;)/revalidateTag('\''products'\'');\n$1/s' "$UPD"
    # Fallback: if the return shape differs, insert before the last line of the handler
    if ! grep -q "revalidateTag('products')" "$UPD"; then
      perl -0777 -i -pe 's/(\}\s*\n\}\s*$)/  revalidateTag('\''products'\'');\n$1/s' "$UPD"
    fi
  fi
fi

# ---------- 4) (Optional) force no-store for list endpoints your UI calls ----------
# If you have route files like app/api/products/route.ts or merged.ts, we can export dynamic='force-dynamic'
for F in app/api/products/route.ts app/api/products/merged/route.ts; do
  if [ -f "$F" ] && ! grep -q "export const dynamic" "$F"; then
    printf "%s\n\n%s\n" "export const dynamic = 'force-dynamic'" "$(cat "$F")" > "$F.tmp" && mv "$F.tmp" "$F"
  fi
done

echo "✅ Fixes applied. Restarting dev server…"
pkill -9 node 2>/dev/null || true
pnpm dev
