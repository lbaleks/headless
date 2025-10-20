'use client';
import * as React from 'react'

type Variant = any
type Props = {
  variants: Variant[]
  onApply: (next: Variant[]) => void
}

/**
 * Minimal bulk editor:
 * - Set a price delta (+/-)
 * - Set a multiplier for all
 * - Toggle enabled for all
 * Calls onApply(next) when you click "Apply to all variants"
 */
export default function BulkVariantEdit({ variants, onApply }: Props) {
  const [priceDelta, setPriceDelta] = React.useState<number>(0)
  const [multiplier, setMultiplier] = React.useState<number | ''>('')
  const [enabled, setEnabled] = React.useState<boolean | null>(null)

  const applyAll = () => {
    const next = (Array.isArray(variants) ? variants : []).map((v) => {
      const copy: any = { ...v }
      if (priceDelta && Number.isFinite(Number(copy.price ?? 0))) {
        copy.price = Number(copy.price ?? 0) + Number(priceDelta)
      }
      if (multiplier !== '' && Number.isFinite(Number(multiplier))) {
        copy.multiplier = Number(multiplier)
      }
      if (enabled !== null) {
        copy.enabled = !!enabled
      }
      return copy
    })
    onApply(next)
  }

  return (
    <div className="rounded-lg border bg-white p-3">
      <div className="text-sm font-medium mb-2">Bulk edit variants</div>
      <div className="flex flex-wrap gap-3 items-end">
        <label className="flex flex-col text-sm">
          <span className="text-neutral-600 mb-1">Price delta</span>
          <input
            type="number"
            className="border rounded px-2 py-1"
            value={String(priceDelta)}
            onChange={(e) => setPriceDelta(Number(e.target.value || 0))}
            placeholder="+5 or -10"
          />
        </label>
        <label className="flex flex-col text-sm">
          <span className="text-neutral-600 mb-1">Multiplier</span>
          <input
            type="number"
            className="border rounded px-2 py-1"
            value={multiplier === '' ? '' : String(multiplier)}
            onChange={(e) => {
              const v = e.target.value
              setMultiplier(v === '' ? '' : Number(v))
            }}
            placeholder="e.g. 1 or 250"
          />
        </label>
        <label className="flex flex-col text-sm">
          <span className="text-neutral-600 mb-1">Enabled</span>
          <select
            className="border rounded px-2 py-1"
            value={enabled === null ? '' : enabled ? 'true' : 'false'}
            onChange={(e) => {
              const v = e.target.value
              setEnabled(v === '' ? null : v === 'true')
            }}
          >
            <option value="">No change</option>
            <option value="true">Enable all</option>
            <option value="false">Disable all</option>
          </select>
        </label>

        <button
          type="button"
          onClick={applyAll}
          className="ml-auto bg-neutral-900 text-white text-sm px-3 py-2 rounded"
        >
          Apply to all variants
        </button>
      </div>
    </div>
  )
}
