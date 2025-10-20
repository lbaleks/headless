'use client';
import React from 'react'
import AdminPage from '@/components/AdminPage'

type Rule={type:string;label:string;price:number;currency?:string}
export default function Pricing(){
  const [rows,setRows]=React.useState<Rule[]|null>(null)
  const [busy,setBusy]=React.useState(false)

  const load=async()=>{
    const j=await fetch('/api/pricing/rules',{cache:'no-store'}).then(r=>r.json()).catch(()=>({rules:[]}))
    setRows(Array.isArray(j.rules)? j.rules : [])
  }
  React.useEffect(()=>{ load() },[])

  const add=()=> setRows(r=>(r||[]).concat({type:'base',label:'New rule',price:0,currency:'NOK'}))
  const del=(i:number)=> setRows(r=>(r||[]).filter((_,ix)=>ix!==i))
  const upd=(i:number,patch:Partial<Rule>)=> setRows(r=>(r||[]).map((x,ix)=>ix===i?{...x,...patch}:x))

  const save=async()=>{
    if(!rows) return
    setBusy(true)
    try{
      const res = await fetch('/api/pricing/rules',{
        method:'PUT',
        headers:{'content-type':'application/json','cache-control':'no-store'},
        body: JSON.stringify({ rules: rows })
      })
      if(!res.ok) throw new Error('Save failed')
      const j = await res.json().catch(()=>null)
      if(Array.isArray(j?.rules)) setRows(j.rules)
      ;(window as any).lbToast?.('Pricing saved')
    }catch(e:any){
      console.error(e); (window as any).lbToast?.('Save failed: '+(e?.message||'Unknown'))
    }finally{ setBusy(false) }
  }

  if(rows===null) return <AdminPage title="Pricing"><div className="p-6">Loading…</div></AdminPage>

  return (
    <AdminPage title="Pricing" actions={<button className="border rounded px-3 py-1.5" onClick={save} disabled={busy}>Save</button>}>
      <div className="overflow-auto">
        <table className="min-w-[800px] text-sm">
          <thead><tr><th className="p-2 text-left">Type</th><th className="p-2 text-left">Label</th><th className="p-2 text-right">Price</th><th className="p-2 text-left">Currency</th><th className="p-2"></th></tr></thead>
          <tbody>
            {rows.map((r,i)=>(
              <tr key={i} className="odd:bg-white even:bg-gray-50">
                <td className="p-2 border-t">
                  <select className="lb-input" value={r.type} onChange={e=>upd(i,{type:e.target.value})}>
                    <option value="base">base</option>
                    <option value="tier">tier</option>
                    <option value="promo">promo</option>
                  </select>
                </td>
                <td className="p-2 border-t"><input className="lb-input w-full" value={r.label} onChange={e=>upd(i,{label:e.target.value})}/></td>
                <td className="p-2 border-t text-right"><input type="number" step="0.01" className="lb-input w-28 text-right" value={r.price} onChange={e=>upd(i,{price:Number(e.target.value||0)})}/></td>
                <td className="p-2 border-t"><input className="lb-input w-24" value={r.currency||'NOK'} onChange={e=>upd(i,{currency:e.target.value})}/></td>
                <td className="p-2 border-t text-right">
                  <button className="text-xs text-red-600" onClick={()=>del(i)}>Remove</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="mt-3">
          <button className="border rounded px-3 py-1.5" onClick={add}>Add rule</button>
        </div>
      </div>
    </AdminPage>
  )
}