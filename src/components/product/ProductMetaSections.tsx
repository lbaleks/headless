'use client';
import React from 'react'

type Product = {
  id:string; name?:string; sku?:string; status?:string; visibility?:string; type?:string
  price?:number; currency?:string; cost?:number
  description?:string; shortDescription?:string
  metaTitle?:string; metaDescription?:string; metaKeywords?:string; urlKey?:string
  taxClass?:string; weight?:number; width?:number; height?:number; length?:number; shippingClass?:string
  brand?:string; categories?:string[]
  options?: { code:string; label:string; enabled?:boolean; priceDelta?:number }[]
  [k:string]:any
}

export default function ProductMetaSections({
  form, setForm
}:{ form:Product|null|undefined; setForm: (u:any)=>void }){
  if(!form) return null
  const upd=(k:string,v:any)=> setForm((f:Product)=> ({...f,[k]:v}))

  return (
    <div className="grid lg:grid-cols-3 gap-6 mt-6">
      {/* LEFT: Description */}
      <div className="lg:col-span-2 space-y-4">
        <section className="rounded-xl border bg-white p-4">
          <div className="text-sm font-medium mb-3">Description</div>
          <textarea className="lb-input w-full h-40" placeholder="Long description"
            value={form.description||''} onChange={e=>upd('description', e.target.value)} />
          <div className="grid md:grid-cols-2 gap-3 mt-3">
            <div>
              <div className="text-xs text-neutral-500 mb-1">Short description</div>
              <textarea className="lb-input w-full h-24"
                value={form.shortDescription||''} onChange={e=>upd('shortDescription', e.target.value)} />
            </div>
            <div>
              <div className="text-xs text-neutral-500 mb-1">URL key (slug)</div>
              <input className="lb-input w-full" placeholder="e.g. mosaic-pellets"
                value={form.urlKey||''} onChange={e=>upd('urlKey', e.target.value)} />
            </div>
          </div>
        </section>

        {/* SEO */}
        <section className="rounded-xl border bg-white p-4">
          <div className="text-sm font-medium mb-3">SEO</div>
          <div className="grid md:grid-cols-2 gap-3">
            <div>
              <div className="text-xs text-neutral-500 mb-1">Meta title</div>
              <input className="lb-input w-full" value={form.metaTitle||''}
                onChange={e=>upd('metaTitle', e.target.value)} />
            </div>
            <div>
              <div className="text-xs text-neutral-500 mb-1">Meta keywords</div>
              <input className="lb-input w-full" value={form.metaKeywords||''}
                onChange={e=>upd('metaKeywords', e.target.value)} />
            </div>
          </div>
          <div className="mt-3">
            <div className="text-xs text-neutral-500 mb-1">Meta description</div>
            <textarea className="lb-input w-full h-24"
              value={form.metaDescription||''} onChange={e=>upd('metaDescription', e.target.value)} />
          </div>
        </section>
      </div>

      {/* RIGHT: Identity/Tax/Shipping/Associations/Options */}
      <div className="space-y-4">
        <section className="rounded-xl border bg-white p-4">
          <div className="text-sm font-medium mb-3">Identity</div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <div className="text-xs text-neutral-500 mb-1">Visibility</div>
              <select className="lb-input w-full" value={form.visibility||'catalog, search'} onChange={e=>upd('visibility', e.target.value)}>
                <option>catalog, search</option><option>catalog</option><option>search</option><option>hidden</option>
              </select>
            </div>
            <div>
              <div className="text-xs text-neutral-500 mb-1">Status</div>
              <select className="lb-input w-full" value={form.status||'enabled'} onChange={e=>upd('status', e.target.value)}>
                <option>enabled</option><option>disabled</option>
              </select>
            </div>
          </div>
        </section>

        <section className="rounded-xl border bg-white p-4">
          <div className="text-sm font-medium mb-3">Tax & Shipping</div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <div className="text-xs text-neutral-500 mb-1">Tax class</div>
              <input className="lb-input w-full" value={form.taxClass||''} onChange={e=>upd('taxClass', e.target.value)} />
            </div>
            <div>
              <div className="text-xs text-neutral-500 mb-1">Shipping class</div>
              <input className="lb-input w-full" value={form.shippingClass||''} onChange={e=>upd('shippingClass', e.target.value)} />
            </div>
            <div>
              <div className="text-xs text-neutral-500 mb-1">Weight (kg)</div>
              <input type="number" step="0.001" className="lb-input w-full" value={form.weight??''} onChange={e=>upd('weight', Number(e.target.value))} />
            </div>
            <div>
              <div className="text-xs text-neutral-500 mb-1">Dimensions (L × W × H cm)</div>
              <div className="flex gap-2">
                <input type="number" className="lb-input w-full" placeholder="L" value={form.length??''} onChange={e=>upd('length', Number(e.target.value))} />
                <input type="number" className="lb-input w-full" placeholder="W" value={form.width??''} onChange={e=>upd('width', Number(e.target.value))} />
                <input type="number" className="lb-input w-full" placeholder="H" value={form.height??''} onChange={e=>upd('height', Number(e.target.value))} />
              </div>
            </div>
          </div>
        </section>

        <section className="rounded-xl border bg-white p-4">
          <div className="text-sm font-medium mb-3">Associations</div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <div className="text-xs text-neutral-500 mb-1">Brand</div>
              <input className="lb-input w-full" value={form.brand||''} onChange={e=>upd('brand', e.target.value)} />
            </div>
            <div>
              <div className="text-xs text-neutral-500 mb-1">Categories (comma)</div>
              <input className="lb-input w-full" placeholder="Hops, Pellets" value={(form.categories||[]).join(', ')}
                onChange={e=>upd('categories', e.target.value.split(',').map(s=>s.trim()).filter(Boolean))} />
            </div>
          </div>
        </section>

        <section className="rounded-xl border bg-white p-4">
          <div className="text-sm font-medium mb-3">Custom options</div>
          <div className="flex items-center gap-2">
            <input id="opt-milling" type="checkbox" checked={!!form.options?.find(o=>o.code==='milling')?.enabled}
              onChange={e=>{
                const curr = form.options||[]
                const i = curr.findIndex(o=>o.code==='milling')
                const next = i>=0 ? curr.map((o,j)=> j===i? {...o, enabled:e.target.checked}:o)
                                  : [...curr, {code:'milling', label:'Kverning', enabled:e.target.checked, priceDelta:0}]
                upd('options', next)
              }} />
            <label htmlFor="opt-milling" className="text-sm">Kverning</label>
          </div>
          <div className="mt-2">
            <div className="text-xs text-neutral-500 mb-1">Price delta (NOK)</div>
            <input type="number" className="lb-input w-full"
              value={form.options?.find(o=>o.code==='milling')?.priceDelta ?? 0}
              onChange={e=>{
                const curr = form.options||[]
                const i = curr.findIndex(o=>o.code==='milling')
                const next = i>=0 ? curr.map((o,j)=> j===i? {...o, priceDelta:Number(e.target.value)}:o)
                                  : [...curr, {code:'milling', label:'Kverning', enabled:true, priceDelta:Number(e.target.value)}]
                upd('options', next)
              }} />
          </div>
        </section>
      </div>
    </div>
  )
}
