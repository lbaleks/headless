#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TARGET_DIR="$ROOT/app/admin/products/[id]"
CLIENT_FILE="$TARGET_DIR/ProductDetail.client.tsx"

echo "→ Sikrer mappe: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

echo "→ Skriver $CLIENT_FILE"
cat > "$CLIENT_FILE" <<'TS'
'use client'
import React from 'react'
import { AdminPage } from '@/src/components/AdminPage'
import { BulkVariantEdit } from '@/src/components/BulkVariantEdit'
import { VariantImages } from '@/src/components/VariantImages'
import type { ProductLike } from '@/types'

type Props = { id: string }

export default function ProductDetail({ id }: Props) {
  const [form, setForm] = React.useState<ProductLike | null>(null)
  const [busy, setBusy] = React.useState(false)
  const [tab, setTab] = React.useState<'main' | 'variants' | 'media' | 'relations'>('main')

  // Hent produkt én gang per id
  React.useEffect(() => {
    let alive = true
    ;(async () => {
      try {
        const res = await fetch(`/api/products/${id}`, { cache: 'no-store' })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = (await res.json()) as ProductLike | null
        if (alive) setForm(data ?? null)
      } catch (e) {
        console.error(e)
        if (alive) setForm(null)
      }
    })()
    return () => { alive = false }
  }, [id])

  // Helper: trygg merge – ingen setState i render
  const update = React.useCallback((patch: Partial<ProductLike>) => {
    setForm(prev => (prev ? { ...prev, ...patch } : { ...(patch as ProductLike) }))
  }, [])

  const save = React.useCallback(async () => {
    if (!form) return
    try {
      setBusy(true)
      const res = await fetch(`/api/products/${form.id ?? id}`, {
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
  }, [form, id])

  // Stable utledninger
  const variants = React.useMemo(() => form?.variants ?? [], [form?.variants])

  return (
    <AdminPage
      title={form?.title ? `Produkt: ${form.title}` : 'Produkt'}
      actions={[
        { label: busy ? 'Saving…' : 'Save', onClick: save, disabled: busy || !form },
      ]}
      tabs={[
        { key: 'main', label: 'Main', active: tab === 'main', onClick: () => setTab('main') },
        { key: 'variants', label: 'Variants', active: tab === 'variants', onClick: () => setTab('variants') },
        { key: 'media', label: 'Media', active: tab === 'media', onClick: () => setTab('media') },
        { key: 'relations', label: 'Relations', active: tab === 'relations', onClick: () => setTab('relations') },
      ]}
    >
      {/* MAIN */}
      {tab === 'main' && (
        <div className="grid grid-cols-1 gap-4">
          <div className="admin-field">
            <label className="admin-label">Title</label>
            <input
              className="admin-input"
              value={form?.title ?? ''}
              onChange={e => update({ title: e.target.value })}
              placeholder="Product title"
            />
          </div>
          <div className="admin-field">
            <label className="admin-label">Description</label>
            <textarea
              className="admin-textarea"
              value={form?.description ?? ''}
              onChange={e => update({ description: e.target.value })}
              placeholder="Description…"
            />
          </div>
          <div className="grid grid-cols-3 gap-4">
            <div className="admin-field">
              <label className="admin-label">Base price</label>
              <input
                className="admin-input"
                type="number"
                value={form?.price ?? 0}
                onChange={e => update({ price: Number(e.target.value || 0) })}
              />
            </div>
            <div className="admin-field">
              <label className="admin-label">Stock</label>
              <input
                className="admin-input"
                type="number"
                value={form?.stock ?? 0}
                onChange={e => update({ stock: Number(e.target.value || 0) })}
              />
            </div>
            <div className="admin-field">
              <label className="admin-label">Active</label>
              <input
                className="admin-checkbox"
                type="checkbox"
                checked={!!form?.active}
                onChange={e => update({ active: e.target.checked })}
              />
            </div>
          </div>
        </div>
      )}

      {/* VARIANTS */}
      {tab === 'variants' && (
        <div className="grid gap-4">
          {/* BulkVariantEdit skal være PURE – ingen setState i render */}
          <BulkVariantEdit
            variants={variants}
            onChange={(next) => {
              // oppdater bare hvis innholdet faktisk endrer seg
              if (variants !== next) update({ variants: next as any })
            }}
          />
          {/* Fallback-tabell hvis komponenten er borte i prosjektet */}
          {(!BulkVariantEdit || (Array.isArray(variants) && variants.length === 0)) && (
            <div className="admin-panel">
              <div className="text-sm text-gray-500">Ingen varianter</div>
            </div>
          )}
        </div>
      )}

      {/* MEDIA */}
      {tab === 'media' && (
        <div className="grid gap-4">
          <VariantImages
            images={form?.images ?? []}
            onChange={(imgs) => update({ images: imgs as any })}
          />
        </div>
      )}

      {/* RELATIONS */}
      {tab === 'relations' && (
        <div className="admin-panel">Relations coming soon…</div>
      )}
    </AdminPage>
  )
}
TS

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next/cache" 2>/dev/null || true
mkdir -p "$ROOT/.next"

echo "✓ Ferdig. Start server på nytt:  npm run dev"
