"use client";
import useSWR from 'swr'
import Link from 'next/link'
import { AttrEditorNumber, AttrEditorText } from '@/components/AttrEditor'

const fetcher=(u:string)=>fetch(u,{cache:'no-store'}).then(r=>r.json())

export default function ProductDetail({sku}:{sku:string}){
  const {data:prod} = useSWR(`/api/products/${encodeURIComponent(sku)}`, fetcher)
  const {data:comp} = useSWR(`/api/products/completeness?sku=${encodeURIComponent(sku)}`, fetcher)
  const {data:audit}= useSWR(`/api/audit/products/${encodeURIComponent(sku)}`, fetcher)

  if(!prod) return <div className="p-4">Laster…</div>
  const item = comp?.items?.[0]
  const score = item?.completeness?.score ?? null

  return (
    <div className="space-y-6 p-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">{prod.name ?? sku}</h1>
        <Link href="/admin/products" className="text-sm underline">← Tilbake</Link>
      </div>

      <div className="grid md:grid-cols-3 gap-4">
        <div className="rounded-xl border p-4">
          <div className="text-sm text-neutral-500 mb-1">SKU</div>
          <div className="font-mono">{sku}</div>
          <div className="mt-4 text-sm text-neutral-500 mb-1">Kilde</div>
          <div className="font-mono">{prod.source}</div>
          {score!==null && (
            <div className="mt-4">
              <div className="text-sm text-neutral-500 mb-1">Completeness</div>
              <div className="inline-flex items-center gap-2 rounded-full border px-3 py-1">
                <span className="text-sm">{score}%</span>
              </div>
            </div>
          )}
        </div>

        <div className="rounded-xl border p-4 md:col-span-2">
          <div className="font-semibold mb-3">Attributter</div>
          <div className="grid sm:grid-cols-2 gap-4">
            <div>
              <div className="text-sm text-neutral-500 mb-1">IBU</div>
              <AttrEditorNumber sku={sku} attr="ibu" step={1} min={0} />
            </div>
            <div>
              <div className="text-sm text-neutral-500 mb-1">Humle</div>
              <AttrEditorText sku={sku} attr="hops" />
            </div>
          </div>
        </div>

        <div className="rounded-xl border p-4 md:col-span-3">
          <div className="font-semibold mb-3">Audit</div>
          {!audit?.items?.length && <div className="text-sm text-neutral-500">Ingen endringer logget.</div>}
          <ul className="space-y-2">
            {audit?.items?.map((e:any, i:number)=>(
              <li key={i} className="rounded border p-3 text-sm">
                <div className="text-neutral-500">{e.ts}</div>
                <pre className="text-xs overflow-auto">{JSON.stringify({before:e.before,after:e.after}, null, 2)}</pre>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  )
}
