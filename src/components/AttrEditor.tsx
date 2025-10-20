"use client";
import {useState,useRef} from 'react'

async function patchAttr(sku:string, attr:string, value:any){
  const r = await fetch('/api/products/update-attributes',{
    method:'PATCH',
    headers:{'content-type':'application/json'},
    body: JSON.stringify({ sku, attributes: { [attr]: value } })
  })
  if(!r.ok) throw new Error(await r.text().catch(()=>r.statusText))
  return r.json()
}

export function AttrEditorNumber({sku, attr, min=0, max=9999, step=1, value:initial}:{sku:string,attr:string,min?:number,max?:number,step?:number,value?:number}){
  const [v,setV]=useState<number|''>(typeof initial==='number'? initial : '')
  const [status,setStatus]=useState<'idle'|'saving'|'saved'|'error'>('idle')
  const timer=useRef<number|undefined>(undefined)

  function scheduleSave(n:number| ''){
    if(n===''){ setV(''); return }
    setV(n); setStatus('saving')
    if(timer.current) window.clearTimeout(timer.current)
    timer.current = window.setTimeout(async ()=>{
      try{ await patchAttr(sku,attr,n); setStatus('saved'); setTimeout(()=>setStatus('idle'),800) }
      catch{ setStatus('error') }
    }, 400)
  }

  return (
    <div className="flex items-center gap-2">
      <input type="number" min={min} max={max} step={step}
             className="w-20 rounded border px-2 py-1"
             value={v} onChange={e=>scheduleSave(e.target.value===''? '' : Number(e.target.value))} />
      <span className={`text-xs ${status==='saving'?'text-amber-600':status==='saved'?'text-emerald-600':status==='error'?'text-rose-600':'text-neutral-400'}`}>
        {status==='saving'?'Lagrer…':status==='saved'?'Lagret':status==='error'?'Feil':' '}
      </span>
    </div>
  )
}

export function AttrEditorText({sku, attr, value:initial}:{sku:string,attr:string,value?:string}){
  const [v,setV]=useState<string>(initial ?? '')
  const [status,setStatus]=useState<'idle'|'saving'|'saved'|'error'>('idle')
  const timer=useRef<number|undefined>(undefined)
  function scheduleSave(n:string){
    setV(n); setStatus('saving')
    if(timer.current) window.clearTimeout(timer.current)
    timer.current = window.setTimeout(async ()=>{
      try{ await patchAttr(sku,attr,n.trim()); setStatus('saved'); setTimeout(()=>setStatus('idle'),800) }
      catch{ setStatus('error') }
    }, 400)
  }
  return (
    <div className="flex items-center gap-2">
      <input type="text" className="w-36 rounded border px-2 py-1"
             value={v} onChange={e=>scheduleSave(e.target.value)} />
      <span className={`text-xs ${status==='saving'?'text-amber-600':status==='saved'?'text-emerald-600':status==='error'?'text-rose-600':'text-neutral-400'}`}>
        {status==='saving'?'Lagrer…':status==='saved'?'Lagret':' '}
      </span>
    </div>
  )
}
