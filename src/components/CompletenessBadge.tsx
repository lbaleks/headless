"use client";
import { useEffect, useState } from 'react'

export default function CompletenessBadge({ sku }: { sku: string }) {
  const [score, setScore] = useState<number | null>(null)
  const [color, setColor] = useState('gray')

  useEffect(() => {
    if (!sku) return
    fetch(`/api/products/completeness?sku=${sku}`)
      .then(res => res.json())
      .then(data => {
        const item = data?.items?.[0]
        if (!item?.completeness?.score) return
        const s = item.completeness.score
        setScore(s)
        setColor(s >= 90 ? 'green' : s >= 70 ? 'yellow' : 'red')
      })
      .catch(() => {})
  }, [sku])

  if (score === null) return <span className="text-sm text-gray-400">Completeness: …</span>

  const label = `${score}%`
  const colorClass =
    color === 'green' ? 'bg-green-100 text-green-700' :
    color === 'yellow' ? 'bg-yellow-100 text-yellow-700' :
    'bg-red-100 text-red-700'

  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-sm font-medium ${colorClass}`}>
      Completeness: {label}
    </span>
  )
}
