#!/usr/bin/env bash
set -euo pipefail
echo "→ Fikser /admin/products/[sku] for Next 15 params + AttributeEditor"

# 1) Server wrapper (page.tsx) — bruker React.use(params)
mkdir -p app/admin/products/[sku]
cat > app/admin/products/[sku]/page.tsx <<'TS'
import React from "react";
import ProductDetail from "./ProductDetail.client";

export default function Page({ params }: { params: Promise<{ sku: string }> }) {
  const { sku } = React.use(params); // Next 15: params er en Promise i server components
  return <ProductDetail sku={decodeURIComponent(sku)} />;
}
TS

# 2) Klient-komponenten (ProductDetail.client.tsx)
cat > app/admin/products/[sku]/ProductDetail.client.tsx <<'TSX'
'use client'

import useSWR from 'swr'
import CompletenessBadge from '@/components/CompletenessBadge'
import AttributeEditor from '@/components/AttributeEditor'

const fetcher = (u: string) => fetch(u).then(r => r.json())

export default function ProductDetail({ sku }: { sku: string }) {
  const { data: prod }  = useSWR(`/api/products/${encodeURIComponent(sku)}`, fetcher)
  const { data: comp }  = useSWR(`/api/products/completeness?sku=${encodeURIComponent(sku)}`, fetcher)

  const name = prod?.name ?? sku
  const score = comp?.items?.[0]?.completeness?.score ?? null

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-semibold">{name}</h1>
        <CompletenessBadge sku={sku} />
      </div>

      <div className="grid md:grid-cols-2 gap-4">
        <div className="p-4 border rounded">
          <h2 className="font-semibold mb-3">Attributes</h2>
          <AttributeEditor sku={sku} />
        </div>

        <div className="p-4 border rounded">
          <h2 className="font-semibold mb-3">Status</h2>
          <div className="text-sm text-neutral-600">
            {score === null ? 'Laster completeness…' : `Completeness: ${score}%`}
          </div>
        </div>
      </div>
    </div>
  )
}
TSX

# 3) Sørg for at AttributeEditor finnes (idempotent, enkel stub hvis mangler)
mkdir -p src/components
if [ ! -f src/components/AttributeEditor.tsx ]; then
  cat > src/components/AttributeEditor.tsx <<'TSX'
'use client'
import { useState } from 'react'

export default function AttributeEditor({ sku }: { sku: string }) {
  const [ibu, setIbu] = useState<number | ''>('')

  async function save() {
    const body = { sku, attributes: {} as Record<string, any> }
    if (ibu !== '') body.attributes.ibu = Number(ibu)
    await fetch('/api/products/update-attributes', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    })
    // ingen hard refresh her – UI kan lytte via SWR mutate i mer avansert versjon
  }

  return (
    <div className="flex gap-2 items-center">
      <label className="text-sm">IBU:</label>
      <input
        className="border rounded px-2 py-1 w-24"
        type="number"
        value={ibu}
        onChange={e => setIbu(e.target.value === '' ? '' : Number(e.target.value))}
        placeholder="e.g. 60"
      />
      <button className="px-3 py-1 border rounded" onClick={save}>Save</button>
    </div>
  )
}
TSX
fi

echo "✓ OK. Restart dev og test siden."
