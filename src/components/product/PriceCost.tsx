'use client';
import React from 'react'
import { Card } from '@/components/ui/Card'

export default function PriceCost({price,cost,onChange}:{price:number;cost:number;onChange?:(p:{price:number;cost:number})=>void}){
  const [pr,setPr]=React.useState(Number(price||0))
  const [co,setCo]=React.useState(Number(cost||0))
  React.useEffect(()=>{ onChange?.({price:pr,cost:co}) },[pr,co])
  const margin=pr-co
  const marginPct=pr? (100*(pr-co)/pr) : 0
  return (
    <Card title="Pricing & Margin">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <label className="block">
          <div className="text-xs text-neutral-500 mb-1">Price</div>
          <input type="number" step="0.01" className="lb-input w-full" value={pr} onChange={e=>setPr(Number(e.target.value||0))}/>
        </label>
        <label className="block">
          <div className="text-xs text-neutral-500 mb-1">Purchase cost</div>
          <input type="number" step="0.01" className="lb-input w-full" value={co} onChange={e=>setCo(Number(e.target.value||0))}/>
        </label>
        <div className="rounded-lg border p-3">
          <div className="text-xs text-neutral-500">Margin</div>
          <div className="text-lg font-semibold">{margin.toFixed(2)} ({marginPct.toFixed(1)}%)</div>
        </div>
      </div>
    </Card>
  )
}