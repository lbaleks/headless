'use client';
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
