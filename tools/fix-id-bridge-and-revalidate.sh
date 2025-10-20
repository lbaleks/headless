#!/bin/bash
set -euo pipefail
echo "🔧 Litebrygg: ID→SKU bridge i /api/products/[sku] + ekstra revalidateTag + clean .next"

# 1) Patch /api/products/[sku]/route.ts med ID-bridge
cat > app/api/products/[sku]/route.ts <<'TS'
// app/api/products/[sku]/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'

export const runtime = 'nodejs'

// Små utiler
function isNumericId(s: string) {
  return /^[0-9]+$/.test(s)
}

async function fetchByEntityId(baseUrl: string, token: string, id: string) {
  // Magento search på entity_id
  const url =
    magentoUrl(
      baseUrl,
      'products?' +
        'searchCriteria[filterGroups][0][filters][0][field]=entity_id&' +
        'searchCriteria[filterGroups][0][filters][0][value]=' + encodeURIComponent(id) + '&' +
        'searchCriteria[filterGroups][0][filters][0][condition_type]=eq&' +
        'searchCriteria[pageSize]=1'
    )

  const res = await fetch(url, { headers: { Authorization: 'Bearer ' + token } })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Search entity_id failed ${res.status}: ${text}`)
  }
  const data = await res.json() as any
  const item = Array.isArray(data?.items) && data.items.length ? data.items[0] : null
  return item
}

export async function GET(_req: Request, ctx: { params: Promise<{ sku: string }> }) {
  try {
    const { sku } = await ctx.params
    const { baseUrl, token } = await getMagentoConfig()

    // Hvis "sku" er tall: slå opp entity_id -> finn faktisk SKU -> hent produkt
    if (isNumericId(sku)) {
      const item = await fetchByEntityId(baseUrl, token, sku)
      if (!item) {
        return NextResponse.json({ error: 'Product not found by entity_id', id: sku }, { status: 404 })
      }
      // Har allerede full produktpayload – returnér direkte
      return NextResponse.json(item)
    }

    // Ellers: vanlig SKU-lookup
    const url = magentoUrl(baseUrl, 'products/' + encodeURIComponent(sku))
    const res = await fetch(url, { headers: { Authorization: 'Bearer ' + token } })
    if (!res.ok) {
      const text = await res.text()
      return NextResponse.json({ error: 'Magento fetch failed', detail: text, url }, { status: res.status })
    }
    const data = await res.json()
    return NextResponse.json(data)
  } catch (e: any) {
    return NextResponse.json({ error: 'Product GET failed', detail: String(e?.message || e) }, { status: 500 })
  }
}
TS

# 2) Legg til ekstra revalidateTag i update-attributes
#    (products:merged brukes ofte av listevisningen)
sed -i.bak "s/revalidateTag('products')/revalidateTag('products'); try { revalidateTag('products:merged') } catch {}/" app/api/products/update-attributes/route.ts || true
rm -f app/api/products/update-attributes/route.ts.bak

# 3) Tøm .next for å unngå pekere til gamle artefakter og tving full rebuild
if [ -d ".next" ]; then
  echo "🧹 Cleaning .next/"
  rm -rf .next
fi

echo "✅ ID-bridge + revalidate oppdatert."
echo "➡  Start på nytt: pnpm dev"
