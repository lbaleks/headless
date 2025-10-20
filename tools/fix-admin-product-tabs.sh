#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"

# 1) AdminPage med tabs
ADMIN_PAGE="$ROOT/src/components/AdminPage.tsx"
mkdir -p "$(dirname "$ADMIN_PAGE")"
cat > "$ADMIN_PAGE" <<'TS'
// Hydration-safe AdminPage med tabs
'use client'

import React from 'react'

export type TabDef = { key: string; label: string }

type Props = {
  title: string
  actions?: React.ReactNode
  tabs?: TabDef[]
  activeTab?: string
  onTabChange?: (key: string) => void
  children: React.ReactNode
}

function TabBar({
  tabs = [],
  active,
  onChange,
}: { tabs?: TabDef[]; active?: string; onChange?: (k: string) => void }) {
  if (!tabs || tabs.length === 0) return null
  return (
    <div className="mt-4 border-b">
      <nav className="flex gap-2">
        {tabs.map(t => {
          const isActive = t.key === active
          const base = 'px-3 py-2 text-sm rounded-t'
          const cls = isActive
            ? base + ' bg-neutral-900 text-white'
            : base + ' text-neutral-700 hover:bg-neutral-200'
          return (
            <button
              key={t.key}
              type="button"
              className={cls}
              onClick={() => onChange?.(t.key)}
            >
              {t.label}
            </button>
          )
        })}
      </nav>
    </div>
  )
}

export function AdminPage({
  title,
  actions,
  tabs,
  activeTab,
  onTabChange,
  children,
}: Props) {
  return (
    <div className="p-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">{title}</h1>
        {actions && <div className="flex items-center gap-2">{actions}</div>}
      </div>

      <TabBar tabs={tabs} active={activeTab} onChange={onTabChange} />

      <div className="mt-4">{children}</div>
    </div>
  )
}

// Gi både named og default export for å tåle begge import-varianter
export default AdminPage
TS

# 2) Oppdater produktdetalj – bruk tabs via AdminPage
PD_CLIENT="$ROOT/app/admin/products/[id]/ProductDetail.client.tsx"
if [ -f "$PD_CLIENT" ]; then
  cat > "$PD_CLIENT" <<'TS'
'use client'

import React from 'react'
import { AdminPage } from '@/src/components/AdminPage'
import { BulkVariantEdit } from '@/src/components/BulkVariantEdit'
import { VariantImages } from '@/src/components/VariantImages'
import type { ProductLike } from '@/types'

export default function ProductDetailClient({ id }: { id: string }) {
  const [form, setForm] = React.useState<ProductLike | null>(null)
  const [busy, setBusy] = React.useState(false)
  const [tab, setTab] = React.useState<'main' | 'variants' | 'media' | 'relations'>('main')

  // Last produkt
  React.useEffect(() => {
    let abort = false
    ;(async () => {
      try {
        const res = await fetch(`/api/products/${id}`, { cache: 'no-store' })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = await res.json()
        if (!abort) setForm(data ?? null)
      } catch (err) {
        if (!abort) setForm(null)
      }
    })()
    return () => { abort = true }
  }, [id])

  const tabs = [
    { key: 'main', label: 'Main' },
    { key: 'variants', label: 'Variants' },
    { key: 'media', label: 'Media' },
    { key: 'relations', label: 'Relations' },
  ] as const

  const update = (patch: Partial<ProductLike>) =>
    setForm(prev => (prev ? { ...prev, ...patch } : prev))

  const save = async () => {
    if (!form) return
    try {
      setBusy(true)
      const method = form.id ? 'PUT' : 'POST'
      const url = form.id ? `/api/products/${form.id}` : '/api/products'
      const res = await fetch(url, {
        method,
        headers: { 'content-type': 'application/json' },
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

  return (
    <AdminPage
      title={form?.title || 'Product'}
      actions={
        <button
          onClick={save}
          disabled={busy || !form}
          className="px-4 py-2 rounded bg-neutral-900 text-white disabled:opacity-50"
        >
          Save
        </button>
      }
      tabs={[...tabs]}
      activeTab={tab}
      onTabChange={t => setTab(t as any)}
    >
      {!form && <div className="p-6 text-sm text-neutral-500">Loading…</div>}

      {form && tab === 'main' && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <label className="block">
            <div className="text-sm mb-1">Title</div>
            <input
              className="w-full border rounded px-3 py-2"
              value={form.title || ''}
              onChange={e => update({ title: e.target.value })}
              placeholder="Product title"
            />
          </label>
          <label className="block">
            <div className="text-sm mb-1">Handle</div>
            <input
              className="w-full border rounded px-3 py-2"
              value={form.handle || ''}
              onChange={e => update({ handle: e.target.value })}
              placeholder="product-handle"
            />
          </label>

          <label className="block md:col-span-2">
            <div className="text-sm mb-1">Description</div>
            <textarea
              className="w-full border rounded px-3 py-2 min-h-[120px]"
              value={form.description || ''}
              onChange={e => update({ description: e.target.value })}
              placeholder="Description…"
            />
          </label>

          <div className="block">
            <div className="text-sm mb-1">Price</div>
            <input
              type="number"
              className="w-full border rounded px-3 py-2"
              value={form.price ?? 0}
              onChange={e => update({ price: Number(e.target.value || 0) })}
              placeholder="0"
            />
          </div>

          <div className="block">
            <div className="text-sm mb-1">Stock</div>
            <input
              type="number"
              className="w-full border rounded px-3 py-2"
              value={form.stock ?? 0}
              onChange={e => update({ stock: Number(e.target.value || 0) })}
              placeholder="0"
            />
          </div>
        </div>
      )}

      {form && tab === 'variants' && (
        <div className="admin-panel">
          <BulkVariantEdit
            variants={Array.isArray((form as any).variants) ? (form as any).variants : []}
            onChange={variants => setForm(f => (f ? { ...(f as any), variants } : f))}
          />
        </div>
      )}

      {form && tab === 'media' && (
        <div className="admin-panel">
          <VariantImages
            productId={form.id}
            images={Array.isArray((form as any).images) ? (form as any).images : []}
            onChange={images => setForm(f => (f ? { ...(f as any), images } : f))}
          />
        </div>
      )}

      {form && tab === 'relations' && (
        <div className="admin-panel">Relations coming soon…</div>
      )}
    </AdminPage>
  )
}
TS
else
  echo "ADVARSEL: Fant ikke $PD_CLIENT – hopper over oppdatering."
fi

# 3) Rydd cache
echo "→ Rydder .next-cache…"
rm -rf "$ROOT/.next" "$ROOT/.next/cache" 2>/dev/null || true
mkdir -p "$ROOT/.next"

echo "✓ Ferdig. Start dev-server på nytt:  npm run dev"
