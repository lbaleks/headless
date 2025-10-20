"use client";
import React from 'react'
/* eslint-disable '@typescript-eslint/no-unused-expressions' */

type ProductSearchProps<T = any> = {
  placeholder?: string
  onFetch: (query: string) => Promise<T[]>
  onPick: (item: T) => void
  onError?: (err: string | null) => void
  // valgfritt: render custom item
  renderItem?: (item: T) => React.ReactNode
  // valgfritt: hent nøkkelfelter
  getKey?: (item: T) => string
  getTitle?: (item: T) => string
  getRight?: (item: T) => string | React.ReactNode
}

export default function ProductSearch<T>({
  placeholder = 'Søk…',
  onFetch,
  onPick,
  onError,
  renderItem,
  getKey = (i:any)=> String(i.id ?? i._id ?? i.uuid),
  getTitle = (i:any)=> String(i.title ?? i.name ?? i.productName ?? 'Uten navn'),
  getRight = (i:any)=> typeof i.price === 'number' ? `${Math.round(i.price)} kr` : ''
}: ProductSearchProps<T>) {
  const [q, setQ] = useState('')
  const [busy, setBusy] = useState(false)
  const [items, setItems] = useState<T[]>([])
  const [ts, setTs] = useState(0)

  // debounced søk
  useEffect(() => {
    let alive = true
    const handle = setTimeout(async () => {
      if (!q.trim()) { setItems([]); onError?.(null); return }
      try {
        setBusy(true)
        const res = await onFetch(q.trim())
        if (alive) { setItems(res); onError?.(null) }
      } catch (e:any) {
        console.error(e)
        alive && onError?.(e?.message || 'Søk feilet')
      } finally {
        alive && setBusy(false)
      }
    }, 250)
    return () => { alive = false; clearTimeout(handle) }
  }, [q, onFetch, onError, ts])

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        <input
          value={q}
          onChange={e => setQ(e.target.value)}
          placeholder={placeholder}
          className="w-full border rounded px-2 py-1.5"
        />
        <button
          onClick={()=> setTs(Date.now())}
          className="px-3 py-1.5 rounded border bg-white"
          title="Søk"
        >
          {busy ? 'Søker…' : 'Søk'}
        </button>
      </div>

      {items.length > 0 && (
        <div className="border rounded divide-y max-h-80 overflow-auto bg-white">
          {items.map((it, idx) => (
            <button
              key={getKey(it) || idx}
              onClick={() => onPick(it)}
              className="w-full text-left px-3 py-2 hover:bg-neutral-50 flex items-center justify-between gap-3"
            >
              <div className="truncate">{renderItem ? renderItem(it) : getTitle(it)}</div>
              <div className="text-sm text-neutral-500 shrink-0">{getRight(it)}</div>
            </button>
          ))}
        </div>
      )}

      {!busy && q.trim() && items.length === 0 && (
        <div className="text-sm text-neutral-500">Ingen treff</div>
      )}
    </div>
  )
}
