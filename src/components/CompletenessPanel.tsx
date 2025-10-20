"use client";
import useSWR from 'swr'
import { useMemo, useState, useEffect } from 'react'

const fetcher = (u:string)=>fetch(u, {cache:'no-store'}).then(r=>r.json())

type Row = {
  sku: string
  name?: string
  family: string
  channel: string
  locale: string
  completeness: { score:number, missing:string[], required:string[] }
}

export default function CompletenessPanel() {
  const [sku, setSku] = useState('')
  const [family, setFamily] = useState<string>('all')
  const [q, setQ] = useState('')

  // families hentes fra akeneo-attributes
  const { data:attrs } = useSWR('/api/akeneo/attributes', fetcher)
  const families: string[] = useMemo(()=>{
    const f = Object.keys(attrs?.families ?? {})
    return ['all', ...f]
  }, [attrs])

  // data: enten single (sku) eller paginert liste
  const qs = new URLSearchParams(
    sku ? { sku } : { page:'1', size:'200' }
  ).toString()

  const { data, isLoading } = useSWR(`/api/products/completeness?${qs}`, fetcher, { revalidateOnFocus:false })
  const items: Row[] = (data?.items ?? []) as Row[]

  // filter lokalt på family + fritekst
  const filtered = useMemo(()=>{
    return items.filter(r=>{
      const okFam = family==='all' || r.family===family
      const txt = `${r.sku} ${r.name??''}`.toLowerCase()
      const okQ  = !q || txt.includes(q.toLowerCase())
      return okFam && okQ
    })
  }, [items, family, q])

  const avg = useMemo(()=>{
    if(!filtered.length) return 0
    return Math.round( filtered.reduce((s,r)=>s + (r.completeness?.score??0), 0) / filtered.length )
  }, [filtered])

  useEffect(()=>{
    // sørg for at family finnes i lista – defaults
    if(families.length && family==='all') return
  }, [families, family])

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2 items-end">
        <div className="flex flex-col">
          <label className="text-xs text-neutral-500">SKU (valgfritt)</label>
          <input value={sku} onChange={e=>setSku(e.target.value)}
                 placeholder="TEST"
                 className="border rounded px-2 py-1" />
        </div>
        <div className="flex flex-col">
          <label className="text-xs text-neutral-500">Family</label>
          <select value={family} onChange={e=>setFamily(e.target.value)}
                  className="border rounded px-2 py-1">
            {families.map(f=><option key={f} value={f}>{f}</option>)}
          </select>
        </div>
        <div className="flex flex-col grow min-w-[180px]">
          <label className="text-xs text-neutral-500">Søk</label>
          <input value={q} onChange={e=>setQ(e.target.value)}
                 placeholder="fritakst på sku/navn"
                 className="border rounded px-2 py-1" />
        </div>
      </div>

      <div className="flex items-center justify-between">
        <div className="text-sm text-neutral-600">
          {isLoading ? 'Laster…' : `Viser ${filtered.length} av ${items.length} (${family})`}
        </div>
        <div className="text-sm">
          Snittscore: <span className="font-semibold">{avg}%</span>
        </div>
      </div>

      <div className="border rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-neutral-50 text-neutral-600">
            <tr>
              <th className="text-left p-2">SKU</th>
              <th className="text-left p-2">Family</th>
              <th className="text-left p-2">Score</th>
              <th className="text-left p-2">Mangler</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((r, i)=>(
              <tr key={r.sku || i} className="border-t hover:bg-neutral-50">
                <td className="p-2 font-mono">{r.sku}</td>
                <td className="p-2">{r.family}</td>
                <td className="p-2">
                  <span className="inline-block min-w-[3ch]">{r.completeness?.score ?? 0}%</span>
                  <div className="h-1.5 bg-neutral-200 rounded mt-1">
                    <div className="h-1.5 bg-emerald-500 rounded" style={{width:`${r.completeness?.score ?? 0}%`}} />
                  </div>
                </td>
                <td className="p-2 text-neutral-700">
                  {r.completeness?.missing?.length
                    ? r.completeness.missing.join(', ')
                    : <span className="text-emerald-600">komplett</span>}
                </td>
              </tr>
            ))}
            {!filtered.length && !isLoading && (
              <tr><td className="p-3 text-neutral-500" colSpan={4}>Ingen treff.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
