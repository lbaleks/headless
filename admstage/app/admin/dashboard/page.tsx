"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
type StockInfo = { ok:boolean; base?:string; upstream?:string; auth?:string };
type Draft = { name?:string; sku?:string; price?:number; stock?:number; description?:string; created?:string };

export default function Dashboard(){
  const [loading, setLoading] = useState(true);
  const [stock, setStock] = useState<StockInfo|null>(null);
  const [drafts, setDrafts] = useState<Draft[]>([]);
  const [log, setLog] = useState("");

  async function refresh(){
    setLoading(true);
    try{
      const [a,b] = await Promise.all([
        fetch("/api/ops/stock").then(r=>r.json()).catch(()=>({ ok:false })),
        fetch("/api/drafts/list").then(r=>r.json()).catch(()=>({ ok:false, items:[] }))
      ]);
      setStock(a as any);
      setDrafts(Array.isArray((b as any)?.items) ? (b as any).items : []);
      setLog(l => "✓ refreshed " + new Date().toLocaleTimeString() + "\n" + l);
    }catch(e:any){
      setLog(l => "⚠️ refresh_failed: " + (e?.message||String(e)) + "\n" + l);
    }finally{ setLoading(false); }
  }
  useEffect(()=>{ refresh(); }, []);
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-medium">Dashboard</h2>
        <button onClick={refresh} className="px-3 py-1.5 rounded-lg border hover:bg-black/5" disabled={loading}>
          {loading ? "Oppdaterer…" : "↻ Oppdater"}
        </button>
      </div>
      <div className="grid md:grid-cols-3 gap-4">
        <div className="rounded-2xl border p-4">
          <div className="text-sm opacity-70 mb-1">Gateway</div>
          <div className="text-base font-medium break-all">{stock?.base ?? "—"}</div>
          <div className="text-xs opacity-70 break-all">{stock?.upstream ?? "—"}</div>
          <div className="mt-2"><span className={"text-xs px-2 py-0.5 rounded-full border " + (stock?.ok ? "bg-green-50" : "bg-red-50")}>
            {stock?.ok ? ("OK" + (stock?.auth ? " ("+stock.auth+")" : "")) : "Feil"}
          </span></div>
        </div>
        <div className="rounded-2xl border p-4">
          <div className="text-sm opacity-70 mb-1">Utkast</div>
          <div className="text-base font-medium">{drafts.length} funnet</div>
          <div className="mt-2 space-y-1 max-h-36 overflow-auto pr-2">
            {drafts.slice(0,6).map((d,i)=>(
              <div key={i} className="text-sm flex items-center justify-between">
                <div className="truncate">{d?.name ?? d?.sku ?? "—"}</div>
                <div className="text-xs opacity-70">
                  {(typeof d?.price==="number" ? String(d.price) : "–")} • {(typeof d?.stock==="number" ? String(d.stock) : "–")}
                </div>
              </div>
            ))}
            {drafts.length===0 && <div className="text-sm opacity-60">Ingen</div>}
          </div>
        </div>
        <div className="rounded-2xl border p-4">
          <div className="text-sm opacity-70 mb-1">Snarveier</div>
          <div className="space-y-2">
            <Link href="/admin/products/overview">Products → Overview</Link><br/>
            <Link href="/api/orders/sync">/api/orders/sync (GET)</Link><br/>
            <Link href="/api/ai/reco">/api/ai/reco (GET)</Link>
          </div>
        </div>
      </div>
      <div className="rounded-2xl border p-4">
        <div className="text-sm opacity-70 mb-1">Statuslogg</div>
        <pre className="text-xs whitespace-pre-wrap break-words max-h-48 overflow-auto">{log || "—"}</pre>
      </div>
    </div>
  );
}
