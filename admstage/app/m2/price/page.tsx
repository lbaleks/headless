"use client";
import { useState } from "react";
import Toast from "@/components/m2/Toast";
import StatCard from "@/components/m2/StatCard";
import { api } from "@/lib/api";

export default function PricePage(){
  const [sku, setSku] = useState("TEST-BLUE-EXTRA");
  const [price, setPrice] = useState("199.00");
  const [toast, setToast] = useState<{k:"success"|"error"|"info"|"warn"; m:string}|null>(null);
  const [log, setLog] = useState("");

  const save = async ()=>{
    setLog("⏳ sender…");
    try{
      const body = { sku, price: Number(price) };
      const data = await api.post("/ops/price/upsert", body);
      setLog(JSON.stringify(data, null, 2));
      setToast({k:"success", m:"Pris oppdatert"});
    }catch(e:any){
      setToast({k:"error", m:e?.message||"Feil"});
      setLog("❌ " + (e?.message||String(e)));
    }
  };

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-3 gap-3">
        <StatCard label="Gateway" value={process.env.NEXT_PUBLIC_GATEWAY_BASE||"n/a"} />
        <StatCard label="SKU" value={sku} />
        <StatCard label="Pris (NOK)" value={price} />
      </div>

      <div className="grid gap-3 max-w-lg">
        <label className="block">
          <div className="text-sm">SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={sku} onChange={e=>setSku(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Pris</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={price} onChange={e=>setPrice(e.target.value)} />
        </label>
        <button onClick={save} className="px-3 py-2 rounded-lg border hover:bg-black/5">Lagre pris</button>

        {toast && <Toast kind={toast.k} msg={toast.m} onDone={()=>setToast(null)} />}
        <pre className="text-xs bg-black/5 p-3 rounded max-h-64 overflow-auto">{log}</pre>
      </div>
    </div>
  );
}
