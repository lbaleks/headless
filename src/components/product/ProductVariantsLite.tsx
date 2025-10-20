'use client';
import * as React from 'react'
import { normMult, effectiveVariantStock, effectiveVariantPrice } from '@/utils/inventory'
import { Field } from '@/components/ui/Field'

type Variant = { id?:string; sku?:string; name?:string; price?:number; stock?:number|null; multiplier?:number|null; attributes?:Record<string,string> }
type Product = { id:string; price?:number; stock?:number; currency?:string; variants?:Variant[] }

export default function ProductVariantsLite({
  product, onChange
}:{ product:Product; onChange:(rows:Variant[])=>void }){
  const rows = product.variants||[]
  const setRow = (ix:number, patch:Partial<Variant>)=>{
    onChange(rows.map((r,i)=> i===ix ? {...r,...patch} : r))
  }
  const addRow = ()=>{
    onChange([...(rows||[]), { id: `v${Date.now()}`, name:'', multiplier:1 }])
  }
  const delRow = (ix:number)=> onChange(rows.filter((_,i)=>i!==ix))

  return (
    <div className="space-y-3">
      <div className="overflow-auto">
        <table className="min-w-[900px] lb-table text-sm">
          <caption className="text-left p-2 text-xs text-neutral-500">
            Multiplier &gt; 1 uten per-variant lager ⇒ bruker produktlager delt på multiplier. Multiplier = 1 ⇒ 1:1 fra produktlager.
          </caption>
          <thead>
            <tr>
              <th className="p-2">Name</th>
              <th className="p-2">SKU</th>
              <th className="p-2">Price</th>
              <th className="p-2">Multiplier</th>
              <th className="p-2">Var. stock</th>
              <th className="p-2">Eff. stock</th>
              <th className="p-2">Eff. price</th>
              <th className="p-2"></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((v,ix)=>{
              const effStock = effectiveVariantStock(product, v)
              const effPrice = effectiveVariantPrice(product, v)
              return (
                <tr key={String(v.id||ix)} className="odd:bg-white even:bg-neutral-50">
                  <td className="p-2"><input className="lb-input" value={v.name||''} onChange={e=>setRow(ix,{name:e.target.value})}/></td>
                  <td className="p-2"><input className="lb-input" value={v.sku||''} onChange={e=>setRow(ix,{sku:e.target.value})}/></td>
                  <td className="p-2"><input type="number" step="0.01" className="lb-input" value={v.price ?? ''} onChange={e=>setRow(ix,{price: e.target.value===''? undefined : Number(e.target.value)})}/></td>
                  <td className="p-2"><input type="number" step="0.01" className="lb-input" value={v.multiplier ?? 1} onChange={e=>setRow(ix,{multiplier: Number(e.target.value)||1})}/></td>
                  <td className="p-2"><input type="number" className="lb-input" value={v.stock ?? ''} onChange={e=>setRow(ix,{stock: e.target.value===''? undefined : Number(e.target.value)})}/></td>
                  <td className="p-2 text-right">{effStock}</td>
                  <td className="p-2 text-right">{effPrice.toFixed(2)} {product.currency||'NOK'}</td>
                  <td className="p-2 text-right"><button className="lb-btn" onClick={()=>delRow(ix)}>Delete</button></td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      <button className="lb-btn" onClick={addRow}>Add variant</button>
    </div>
  )
}
