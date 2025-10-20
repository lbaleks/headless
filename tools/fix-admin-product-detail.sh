#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "→ Oppretter/oppdaterer filer…"

# --- Server-side page: unwrap params (Next 15)
cat > app/admin/products/[id]/page.tsx <<'TSX'
import React from 'react'
import ProductDetail from './ProductDetail.client'

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return <ProductDetail id={id} />
}
TSX

# --- Client-side component med robuste imports og enkel UI
cat > app/admin/products/[id]/ProductDetail.client.tsx <<'TSX'
'use client'

import React, { useEffect, useState } from 'react'
import { AdminPage } from '@/src/components/AdminPage'
// Robust import: støtter både named og default eksport
import * as BulkVariantEditMod from '@/src/components/BulkVariantEdit'
const BulkVariantEdit = (BulkVariantEditMod as any).BulkVariantEdit ?? (BulkVariantEditMod as any).default
import * as VariantImagesMod from '@/src/components/VariantImages'
const VariantImages = (VariantImagesMod as any).VariantImages ?? (VariantImagesMod as any).default

import type { ProductLike } from '@/types'

export default function ProductDetail({ id }: { id: string }) {
  const [form, setForm] = useState<ProductLike | null>(null)
  const [busy, setBusy] = useState(false)
  const [tab, setTab] = useState<'main'|'variants'|'media'|'relations'>('main')

  // Last produkt
  useEffect(() => {
    let abort = false
    ;(async () => {
      try {
        const res = await fetch(`/api/products/${id}`, { cache: 'no-store' })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = await res.json()
        if (!abort) setForm(data ?? null)
      } catch (err) {
        console.error(err)
        if (!abort) setForm(null)
      }
    })()
    return () => { abort = true }
  }, [id])

  // Lagre
  const save = async () => {
    if (!form) return
    try {
      setBusy(true)
      const res = await fetch(`/api/products/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })
      if (res.ok) {
        ;(window as any).lbToast?.('Product saved')
      } else {
        ;(window as any).lbToast?.('Save failed')
      }
    } catch (e) {
      console.error(e)
      ;(window as any).lbToast?.('Save failed')
    } finally {
      setBusy(false)
    }
  }

  const update = (patch: Partial<ProductLike>) => setForm(prev => ({ ...(prev ?? {} as ProductLike), ...patch }))

  return (
    <AdminPage
      title={form ? (form.title || `Product ${id}`) : `Product ${id}`}
      primaryAction={{ label: busy ? 'Saving…' : 'Save', onClick: save, disabled: busy || !form }}
      tabs={[
        { id: 'main', label: 'General' },
        { id: 'variants', label: 'Variants' },
        { id: 'media', label: 'Media' },
        { id: 'relations', label: 'Relations' },
      ]}
      currentTab={tab}
      onTabChange={(t) => setTab(t as any)}
    >
      {!form ? (
        <div className="p-6">Loading…</div>
      ) : (
        <div className="p-6 space-y-6">
          {tab === 'main' && (
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium mb-1">Title</label>
                <input
                  className="w-full rounded border px-3 py-2"
                  value={form.title ?? ''}
                  onChange={(e) => update({ title: e.target.value })}
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">Description</label>
                <textarea
                  className="w-full rounded border px-3 py-2 min-h-[120px]"
                  value={(form as any).description ?? ''}
                  onChange={(e) => update({ ...(form as any), description: e.target.value } as any)}
                />
              </div>
            </div>
          )}

          {tab === 'variants' && BulkVariantEdit ? (
            <div className="space-y-4">
              {/* @ts-ignore - støtter både default og named komponent */}
              <BulkVariantEdit product={form} onChange={(p: ProductLike) => setForm(p)} />
            </div>
          ) : null}

          {tab === 'media' && VariantImages ? (
            <div className="space-y-4">
              {/* @ts-ignore - støtter både default og named komponent */}
              <VariantImages product={form} onChange={(p: ProductLike) => setForm(p)} />
            </div>
          ) : null}

          {tab === 'relations' && (
            <div className="admin-panel mt-4">Relations coming soon…</div>
          )}
        </div>
      )}
    </AdminPage>
  )
}
TSX

# --- Rydd opp escape-feil i template literals (for sikkerhets skyld)
node - <<'NODE'
const fs = require('fs');
const p = 'app/admin/products/[id]/ProductDetail.client.tsx';
let s = fs.readFileSync(p, 'utf8');
s = s.replace(/\\`/g, '`').replace(/\\\$\{/g, '${');
fs.writeFileSync(p, s);
console.log('✓ Template-literals OK i', p);
NODE

echo "→ Rydder .next-cache…"
rm -rf .next

echo "✓ Ferdig. Start dev-server på nytt (npm run dev) og hard-reload i nettleseren (cmd+shift+R)."
