"use client";
import AttributeEditor from "@/components/AttributeEditor";import * as React from 'react'
import { useParams } from 'next/navigation'
import Tabs from '@/components/ui/Tabs'
import { Field } from '@/components/ui/Field'
import ProductOptions from '@/components/product/ProductOptions'
import ProductSEO from '@/components/product/ProductSEO'
import ProductMedia from '@/components/product/ProductMedia'
import ProductVariantsLite from '@/components/product/ProductVariantsLite'
import { applyOptionsPriceDelta } from '@/utils/inventory'

type Variant = { id?:string; sku?:string; name?:string; price?:number; stock?:number|null; multiplier?:number|null; attributes?:Record<string,string> }
type OptionRow = { key:string; label:string; enabled:boolean; priceDelta?:number }
type MediaItem = { url:string; alt?:string }

type Product = {
  id:string; name?:string; sku?:string; price?:number; currency?:string; stock?:number;
  description?:string;
  variants?:Variant[];
  options?:OptionRow[];
  media?:MediaItem[];
  slug?:string; metaTitle?:string; metaDescription?:string;
}

export default function ProductAdvanced(){
  const params = useParams() as { id:string }
  const id = String(params.id)
  const [tab, setTab] = React.useState('overview')
  const [busy, setBusy] = React.useState(false)
  const [p, setP] = React.useState<Product|null>(null)

  React.useEffect(()=>{ (async()=>{
    const j = await fetch(`/api/products/${id}`, { cache:'no-store' }).then(r=>r.json()).catch(()=>null)
    setP(j || null)
  })() },[id])

  const save = async (patch:Partial<Product>)=>{
    if(!p) return
    setBusy(true)
    const body = { ...p, ...patch }
    const res = await fetch(`/api/products/${id}`, { method:'PUT', headers:{'content-type':'application/json'}, body: JSON.stringify(body) })
    const j = await res.json().catch(()=>null)
    setBusy(false)
    if(j?.ok && j.product){ setP(j.product); (window as any).lbToast?.('Saved') }
    else (window as any).lbToast?.('Save failed')
  }

  if(!p) return <div className="text-neutral-500">Loading…</div>

  const tabs = [
    { key:'overview', label:'Overview' },
    { key:'variants', label:'Variants' },
    { key:'options',  label:'Options' },
    { key:'media',    label:'Media' },
    { key:'seo',      label:'SEO' },
  ]

  const basePrice = Number(p.price||0)
  const effWithOptions = applyOptionsPriceDelta(basePrice, (p.options||[]).filter(o=>o.enabled))

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div className="flex-1">
          <div className="text-xl font-semibold">{p.name||'Untitled'}</div>
          <div className="text-sm text-neutral-500">SKU: {p.sku||'—'}</div>
        </div>
        <button className="lb-btn" disabled={busy} onClick={()=>save({})}>
          {busy?'Saving…':'Save'}
        </button>
      </div>

      <Tabs tabs={tabs} active={tab} onChange={setTab} />

      <div className="admin-panel p-4 mt-2">
        {tab==='overview' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <Field label="Name">
                <input className="lb-input" value={p.name||''} onChange={e=>setP({...p, name:e.target.value})} onBlur={()=>save({name:p.name})}/>
              </Field>
              <Field label="SKU (auto set if empty on save)">
                <input className="lb-input" value={p.sku||''} onChange={e=>setP({...p, sku:e.target.value})} onBlur={()=>save({sku:p.sku})}/>
              </Field>
              <Field label="Base price">
                <input type="number" step="0.01" className="lb-input" value={p.price ?? 0}
                  onChange={e=>setP({...p, price:Number(e.target.value)||0})}
                  onBlur={()=>save({price:p.price})}/>
              </Field>
              <Field label="Base stock">
                <input type="number" className="lb-input" value={p.stock ?? 0}
                  onChange={e=>setP({...p, stock:Number(e.target.value)||0})}
                  onBlur={()=>save({stock:p.stock})}/>
              </Field>
            </div>
            <div>
              <Field label="Description">
                <textarea rows={8} className="lb-input"
                  value={p.description||''}
                  onChange={e=>setP({...p,description:e.target.value})}
                  onBlur={()=>save({description:p.description})}/>
              </Field>
              <div className="text-sm text-neutral-600">
                Effective price with enabled options: <b>{effWithOptions.toFixed(2)} {p.currency||'NOK'}</b>
              </div>
            </div>
          </div>
        )}

        {tab==='variants' && (
          <ProductVariantsLite product={p} onChange={(rows)=>{ setP({...p,variants:rows}); save({variants:rows}) }} />
        )}

        {tab==='options' && (
          <ProductOptions value={p.options||[]} onChange={(rows)=>{ setP({...p,options:rows}); save({options:rows}) }} />
        )}

        {tab==='media' && (
          <ProductMedia value={p.media||[]} onChange={(rows)=>{ setP({...p,media:rows}); save({media:rows}) }} />
        )}

        {tab==='seo' && (
          <ProductSEO value={p} onChange={(patch)=>{ const next={...p,...patch}; setP(next); save(patch) }} />
        )}
      </div>
    </div>
  )
}
