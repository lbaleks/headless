'use client';
import * as React from 'react'
import AdminPage from '@/components/AdminPage'
import { suggestSku } from '@/utils/sku'

export default function NewProduct(){
  const [f,setF]=React.useState<any>({status:'draft', margin:0.3, stock:0, price:0})
  const change=(k:string,v:any)=>setF((p:any)=>({...p,[k]:v}))
  const onName=(v:string)=>{
    change('name',v)
    if(!f.sku || !String(f.sku).trim()) change('sku', suggestSku(v))
  }
  const create=async()=>{
    const body={...f, sku: (f.sku&&String(f.sku).trim())?f.sku:suggestSku(f.name)}
    const r=await fetch('/api/products',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)})
    if(r.ok){ location.href='/admin/products' } else { (window as any).lbToast?.('Create failed') }
  }
  return (
    <AdminPage
      title="New product"
      actions={<button className="btn-primary" onClick={create}>Create</button>}
    >
      <div className="admin-panel p-4 mt-4">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="lb-label">ID</label>
            <input className="lb-input" value={f.id||''} onChange={e=>change('id',e.target.value)} placeholder="e.g. m1"/>
          </div>
          <div>
            <label className="lb-label">SKU</label>
            <input className="lb-input" value={f.sku||''} onChange={e=>change('sku',e.target.value)} placeholder="auto from name if empty"/>
          </div>
          <div>
            <label className="lb-label">Name</label>
            <input className="lb-input" value={f.name||''} onChange={e=>onName(e.target.value)} />
          </div>
          <div>
            <label className="lb-label">Price</label>
            <input type="number" className="lb-input" value={f.price??0} onChange={e=>change('price',Number(e.target.value)||0)} />
          </div>
          <div>
            <label className="lb-label">Category</label>
            <input className="lb-input" value={f.category||''} onChange={e=>change('category',e.target.value)} />
          </div>
          <div>
            <label className="lb-label">Stock</label>
            <input type="number" className="lb-input" value={f.stock??0} onChange={e=>change('stock',Number(e.target.value)||0)} />
          </div>
          <div>
            <label className="lb-label">Margin</label>
            <input type="number" step="0.01" className="lb-input" value={f.margin??0} onChange={e=>change('margin',Number(e.target.value)||0)} />
          </div>
          <div>
            <label className="lb-label">Status</label>
            <select className="lb-input" value={f.status||'draft'} onChange={e=>change('status',e.target.value)}>
              <option value="draft">draft</option>
              <option value="active">active</option>
              <option value="archived">archived</option>
            </select>
          </div>
        </div>
      </div>
    </AdminPage>
  )
}
