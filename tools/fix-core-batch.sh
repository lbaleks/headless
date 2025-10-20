#!/bin/bash
set -e

echo "🧭 Litebrygg Core Autoinstaller – batch fix (params, NOW, update-attributes)"

# 1️⃣ Fjern duplikate NOW-linjer
grep -rl "const NOW = NOW" app/admin/customers 2>/dev/null | while read -r file; do
  echo "🧹 Rydder duplikate NOW i $file"
  sed -i.bak '/const NOW = NOW/d' "$file"
done

# 2️⃣ Sørg for await på ctx.params i products/[sku]/route.ts
SKU_ROUTE="app/api/products/[sku]/route.ts"
if [ -f "$SKU_ROUTE" ]; then
  echo "🔁 Oppdaterer ctx.params i $SKU_ROUTE"
  sed -i.bak 's|ctx: { params: { sku: string } }|ctx: { params: Promise<{ sku: string }> }|' "$SKU_ROUTE" || true
  sed -i.bak 's|const { sku } = ctx.params|const { sku } = await ctx.params|' "$SKU_ROUTE" || true
fi

# 3️⃣ Opprett / overskriv update-attributes-route.ts
ATTR_ROUTE="app/api/products/update-attributes/route.ts"
echo "🧱 Erstatter $ATTR_ROUTE med sikker versjon"
cat <<'EOF' > "$ATTR_ROUTE"
// app/api/products/update-attributes/route.ts
import { NextResponse } from 'next/server'
import { revalidateTag } from 'next/cache'

type UpdatePayload = {
  sku: string
  attributes: Record<string, any>
}

async function handleUpdate(req: Request) {
  try {
    const body = (await req.json()) as UpdatePayload
    if (!body || !body.sku || !body.attributes) {
      return NextResponse.json(
        { error: 'Missing "sku" or "attributes" in body' },
        { status: 400 },
      )
    }

    const magentoUrl = process.env.MAGENTO_URL || ''
    const magentoToken = process.env.MAGENTO_TOKEN || ''
    if (!magentoUrl || !magentoToken) {
      return NextResponse.json(
        { error: 'Missing MAGENTO_URL or MAGENTO_TOKEN env vars' },
        { status: 500 },
      )
    }

    const url = magentoUrl.replace(/\/+$/, '') + '/rest/V1/products/' + encodeURIComponent(body.sku)

    const result = await fetch(url, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + magentoToken,
      },
      body: JSON.stringify({ product: { ...body.attributes } }),
    })

    if (!result.ok) {
      const text = await result.text()
      return NextResponse.json(
        { error: 'Magento update failed', detail: text },
        { status: result.status || 500 },
      )
    }

    revalidateTag('products')
    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json(
      { error: 'Update attributes failed', detail: String(e?.message || e) },
      { status: 500 },
    )
  }
}

export async function PATCH(req: Request) {
  return handleUpdate(req)
}

export async function POST(req: Request) {
  return handleUpdate(req)
}
EOF

# 4️⃣ Fjern backupfiler
find app -name "*.bak" -delete

# 5️⃣ Valider miljøvariabler
if [[ -z "$MAGENTO_URL" || -z "$MAGENTO_TOKEN" ]]; then
  echo "⚠️  ADVARSEL: MAGENTO_URL eller MAGENTO_TOKEN mangler i miljøet ditt!"
  echo "Legg til i .env.local før du starter dev-server:"
  echo "MAGENTO_URL=https://din-magento-url"
  echo "MAGENTO_TOKEN=XXXXXX"
fi

# 6️⃣ Ferdig
echo "✅ Fix fullført."
echo "🚀 Start Next.js på nytt:"
echo "   pnpm dev"