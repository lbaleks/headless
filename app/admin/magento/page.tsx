'use client';
import { useEffect, useState } from 'react'
import AdminPage from '@/components/AdminPage'

export default function MagentoAdmin(){
  const [h,setH]=useState<any>(null)
  const [busy,setBusy]=useState(false)
  const load=async()=>{ const r=await fetch('/api/magento/health',{cache:'no-store'}); setH(await r.json()) }
  useEffect(()=>{ load() },[])
  const post=async(url:string)=>{ setBusy(true); await fetch(url,{method:'POST'}); setBusy(false); (window as any).lbToast?.('Sync completed') }

  return (
    <AdminPage title="Magento Integration" actions={<button className="border rounded-lg px-3 py-1.5" onClick={load} disabled={busy}>Refresh</button>}>
      <div className="p-6 grid md:grid-cols-2 gap-4">
        <div className="rounded-xl border p-4">
          <div className="text-sm text-neutral-500 mb-2">Status</div>
          {h?(
            <div className="space-y-1 text-sm">
              <div>OK: <b>{String(!!h.ok)}</b> {h.mock && <span className="ml-2 text-xs px-2 py-0.5 rounded bg-yellow-100 text-yellow-800">MOCK</span>}</div>
              <div>Base: <code>{h.base||'—'}</code></div>
              <div>Time: {h.ts||'—'}</div>
            </div>
          ):<div>Loading…</div>}
        </div>
        <div className="rounded-xl border p-4">
          <div className="text-sm text-neutral-500 mb-2">Actions</div>
          <div className="flex flex-wrap gap-2">
            <button className="border rounded-lg px-3 py-1.5 bg-black text-white" onClick={()=>post('/api/magento/sync/products')} disabled={busy}>Sync Products</button>
            <button className="border rounded-lg px-3 py-1.5 bg-black text-white" onClick={()=>post('/api/magento/sync/orders')} disabled={busy}>Sync Orders</button>
          </div>
          <div className="text-xs text-neutral-500 mt-2">Bruker .env for creds. Uten creds kjøres mock-data fra <code>data/magento/*</code>.</div>
        </div>
      </div>
    </AdminPage>
  )
}
