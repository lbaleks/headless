"use client";
import { useState } from "react";
async function j(path:string, init?:RequestInit){ const r=await fetch(path,{cache:"no-store",...init}); const d=await r.json().catch(()=>null); if(!r.ok) throw new Error(d?.error||`HTTP ${r.status}`); return d; }
export default function DevOpsBar(){
  const [msg,setMsg]=useState("");
  async function run(lbl:string, path:string){ setMsg(lbl+"…"); try{ const d=await j(path,{method:"DELETE"}); setMsg(lbl+" ok: "+(d?.total??"")); }catch(e:any){ setMsg(lbl+" feilet: "+(e?.message||e)); } }
  return (
    <div className="flex flex-wrap gap-2">
      <button onClick={()=>run("Seed products (5)","/api/products?action=seed&n=5")} className="px-3 py-1 border rounded bg-white text-sm">Seed products ×5</button>
      <button onClick={()=>run("Seed customers (5)","/api/customers?action=seed&n=5")} className="px-3 py-1 border rounded bg-white text-sm">Seed customers ×5</button>
      {/* Hvis du har en egen orders seed-endpoint, legg til her på samme måte */}
      {msg && <span className="text-xs text-neutral-500">{msg}</span>}
    </div>
  );
}
