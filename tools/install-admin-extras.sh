#!/usr/bin/env bash
set -euo pipefail

ROOT=$(pwd)
APP_DIR="$ROOT/app/admin"
CMP_DIR="$ROOT/components/admin"
LIB_DIR="$ROOT/lib"

echo "🧩 Admin extras: dashboard + sync/seed + UI-komponenter"

mkdir -p "$APP_DIR/dashboard" "$CMP_DIR" "$LIB_DIR"

# ── 1) Legg til Dashboard-lenke i layout (idempotent)
LAY="$APP_DIR/layout.tsx"
if [ -f "$LAY" ] && ! grep -q 'href="/admin/dashboard"' "$LAY"; then
  perl -0777 -pe 's/(<nav[^>]*>.*?)(<Link href="\/admin\/products".*?<\/Link>)/$1$2\n            <Link href="\/admin\/dashboard" className="hover:underline">Dashboard<\/Link>/s' -i "$LAY" || true
fi

# ── 2) Felles “API helper” (beholder eksisterende lib/api.ts hvis finnes)
cat >"$LIB_DIR/admin-actions.ts" <<'TS'
export async function call(path:string, init?:RequestInit){
  const r = await fetch(path, { cache:'no-store', ...init, headers:{'content-type':'application/json', ...(init?.headers||{})}});
  let data:any=null; try{ data = await r.json(); }catch{}
  if(!r.ok) throw new Error(data?.error||`HTTP ${r.status}`);
  return data;
}
TS

# ── 3) Sync- og DevOps-knapper
cat >"$CMP_DIR/SyncButtons.tsx" <<'TSX'
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
TSX

cat >"$CMP_DIR/DevOpsBar.tsx" <<'TSX'
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
TSX

# ── 4) Dashboard-side
cat >"$APP_DIR/dashboard/page.tsx" <<'TSX'
import SyncButtons from "@/components/admin/SyncButtons";
import DevOpsBar from "@/components/admin/DevOpsBar";

async function fetchJson<T>(path:string):Promise<T>{
  const r = await fetch(path, { cache: "no-store" });
  if(!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json() as Promise<T>;
}

type ListResp<T> = { total:number; items:T[] };

export default async function Dashboard(){
  const [prods, custs, ords] = await Promise.all([
    fetchJson<ListResp<any>>("/api/products?page=1&size=1").catch(()=>({total:0,items:[]})),
    fetchJson<ListResp<any>>("/api/customers?page=1&size=1").catch(()=>({total:0,items:[]})),
    fetchJson<ListResp<any>>("/api/orders?page=1&size=1").catch(()=>({total:0,items:[]})),
  ]);

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card title="Products" value={prods.total}/>
        <Card title="Customers" value={custs.total}/>
        <Card title="Orders" value={ords.total}/>
      </div>

      <section className="space-y-2">
        <h2 className="text-sm font-medium text-neutral-700">Sync</h2>
        <SyncButtons />
      </section>

      <section className="space-y-2">
        <h2 className="text-sm font-medium text-neutral-700">Dev data</h2>
        <DevOpsBar />
      </section>

      <section className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <MiniList title="Latest product" rows={prods.items.map(p=>({a:p.sku, b:p.name, c:p.source}))} />
        <MiniList title="Latest customer" rows={custs.items.map(c=>({a:c.id, b:c.email, c:c.source}))} />
        <MiniList title="Latest order" rows={ords.items.map(o=>({a:o.id, b:o.status, c:o.source}))} />
      </section>
    </div>
  );
}

function Card({title,value}:{title:string; value:number}){
  return (
    <div className="border rounded-2xl bg-white px-4 py-5">
      <div className="text-sm text-neutral-500">{title}</div>
      <div className="text-3xl font-semibold mt-1">{value ?? 0}</div>
    </div>
  );
}
function MiniList({title,rows}:{title:string; rows:{a:any,b:any,c:any}[]}){
  return (
    <div className="border rounded-2xl bg-white overflow-hidden">
      <div className="px-4 py-2 text-sm font-medium border-b bg-neutral-50">{title}</div>
      <div className="divide-y">
        {rows.length===0 && <div className="px-4 py-3 text-sm text-neutral-500">—</div>}
        {rows.map((r,i)=>(
          <div key={i} className="px-4 py-3 text-sm flex items-center gap-3">
            <div className="w-28 text-neutral-500 truncate">{String(r.a)}</div>
            <div className="flex-1 truncate">{String(r.b)}</div>
            <div className="text-xs border rounded px-2 py-[2px] bg-neutral-100">{String(r.c||"")}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
TSX

echo "✅ Admin extras installert."