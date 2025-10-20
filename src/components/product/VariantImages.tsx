'use client';
import * as React from 'react'

type Variant = { id?: string | number; name?: string; images?: string[] }
type Props = {
  variants: Variant[]
  onChange?: (next: Variant[]) => void
}

/**
 * Minimal variant image editor:
 * - Shows current image URLs
 * - Lets you add/remove URLs (text-based; easy to wire to your upload flow)
 */
export default function VariantImages({ variants, onChange }: Props) {
  const [local, setLocal] = React.useState<Variant[]>(
    Array.isArray(variants)
      ? variants.map((v) => ({ ...v, images: Array.isArray(v.images) ? v.images : [] }))
      : []
  )

  React.useEffect(() => {
    setLocal(
      Array.isArray(variants)
        ? variants.map((v) => ({ ...v, images: Array.isArray(v.images) ? v.images : [] }))
        : []
    )
  }, [variants])

  const pushChange = (next: Variant[]) => {
    setLocal(next)
    onChange?.(next)
  }

  const addImage = (idx: number) => {
    const url = prompt('Image URL')
    if (!url) return
    const next = local.map((v, i) => (i === idx ? { ...v, images: [...(v.images || []), url] } : v))
    pushChange(next)
  }

  const removeImage = (vIdx: number, imgIdx: number) => {
    const next = local.map((v, i) =>
      i === vIdx ? { ...v, images: (v.images || []).filter((_, j) => j !== imgIdx) } : v
    )
    pushChange(next)
  }

  return (
    <div className="rounded-lg border bg-white p-3">
      <div className="text-sm font-medium mb-2">Variant images</div>
      <div className="space-y-3">
        {(local || []).map((v, i) => (
          <div key={String(v.id ?? i)} className="border rounded p-2">
            <div className="flex items-center justify-between">
              <div className="text-sm font-medium">{v.name || `Variant #${i + 1}`}</div>
              <button
                type="button"
                onClick={() => addImage(i)}
                className="text-sm px-2 py-1 rounded border"
              >
                + Add image URL
              </button>
            </div>
            <ul className="mt-2 flex flex-wrap gap-2">
              {(v.images || []).map((u, j) => (
                <li key={String(j)} className="flex items-center gap-2 text-xs">
                  <a href={u} target="_blank" rel="noreferrer" className="underline">{u}</a>
                  <button
                    type="button"
                    onClick={() => removeImage(i, j)}
                    className="px-2 py-0.5 border rounded"
                  >
                    remove
                  </button>
                </li>
              ))}
              {(v.images || []).length === 0 && (
                <li className="text-xs text-neutral-500">No images</li>
              )}
            </ul>
          </div>
        ))}
      </div>
    </div>
  )
}
