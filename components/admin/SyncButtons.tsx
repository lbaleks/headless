"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
async function j(path:string, init?:RequestInit){ const r=await fetch(path,{cache:"no-store",...init,headers:{'content-type':'application/json',...(init?.headers||{})}}); const d=await r.json().catch(()=>null); if(!r.ok) throw new Error(d?.error||`HTTP ${r.status}`); return d; }
export default function SyncButtons(){
  const [busy, setBusy] = useState<string|false>(false);
  const [msg, setMsg] = useState<string>("");
  const router = useRouter();
  async function run(lbl:string, fn:()=>Promise<any>){
    setBusy(lbl); setMsg("");
    try{ const d = await fn(); setMsg(`${lbl} ok: ${JSON.stringify(d)}`); router.refresh(); }
    catch(e:any){ setMsg(`${lbl} feilet: ${e?.message||e}`); }
    finally{ setBusy(false); }
  }
  return (
    <div className="flex flex-wrap gap-2">
      <button disabled={!!busy} onClick={()=>run("Sync products", ()=>j("/api/products/sync",{method:"POST"}))} className="px-3 py-1 border rounded bg-white text-sm">Sync products</button>
      <button disabled={!!busy} onClick={()=>run("Sync customers",()=>j("/api/customers/sync",{method:"POST"}))} className="px-3 py-1 border rounded bg-white text-sm">Sync customers</button>
      <button disabled={!!busy} onClick={()=>run("Sync orders",  ()=>j("/api/orders/sync",{method:"POST"}))}   className="px-3 py-1 border rounded bg-white text-sm">Sync orders</button>
      {msg && <span className="text-xs text-neutral-500">{busy? "…" : msg}</span>}
    </div>
  );
}
