#!/bin/bash
set -e

echo "🔧 Litebrygg autoinstaller: patching duplikater og ctx.params..."

# 1️⃣ Fjern duplikate NOW-linjer
grep -rl "const NOW = NOW" app/admin/customers | while read -r file; do
  echo "🧹 Fixer duplikate NOW i $file"
  sed -i.bak '/const NOW = NOW/d' "$file"
done

# 2️⃣ Fiks importen av revalidateTag
grep -rl "047next/cache047" app/api | while read -r file; do
  echo "🧭 Retter revalidateTag-import i $file"
  sed -i.bak "s|047next/cache047|next/cache|g" "$file"
done

# 3️⃣ Oppdater ctx.params await-mønster i products-endepunkt
PRODUCT_ROUTE="app/api/products/[sku]/route.ts"
if grep -q "ctx.params" "$PRODUCT_ROUTE"; then
  echo "🔁 Oppdaterer ctx.params-mønster i $PRODUCT_ROUTE"
  sed -i.bak 's|ctx: { params: { sku: string } }|ctx: { params: Promise<{ sku: string }> }|' "$PRODUCT_ROUTE"
  sed -i '' 's|const { sku } = ctx.params|const { sku } = await ctx.params|' "$PRODUCT_ROUTE"
fi

# 4️⃣ Sikre at revalidateTag trigges etter lagring
UPDATE_ATTR="app/api/products/update-attributes/route.ts"
if grep -q "revalidateTag" "$UPDATE_ATTR"; then
cat <<'EOF' > "$UPDATE_ATTR"
import { NextResponse } from 'next/server'
import { revalidateTag } from 'next/cache'

export async function POST(req: Request) {
  try {
    const body = await req.json()
    const { sku, attributes } = body

    const result = await fetch(\`\${process.env.MAGENTO_URL}/rest/V1/products/\${sku}\`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: \`Bearer \${process.env.MAGENTO_TOKEN}\`,
      },
      body: JSON.stringify({ product: { ...attributes } }),
    })

    if (!result.ok) {
      const text = await result.text()
      throw new Error(\`Magento update failed: \${text}\`)
    }

    // 🔁 Tving oppdatering i produkt-cache + completeness
    revalidateTag('products')
    return NextResponse.json({ success: true })
  } catch (e: any) {
    console.error('Update attributes failed', e)
    return NextResponse.json({ error: e.message }, { status: 500 })
  }
}
EOF
fi

echo "✅ Patching fullført. Rydding..."
find app -name "*.bak" -delete

echo "🚀 Ferdig! Kjør dev-server på nytt:"
echo "   pnpm dev"