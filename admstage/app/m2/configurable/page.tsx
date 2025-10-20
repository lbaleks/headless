"use client";
import { useState } from "react";
import Toast from "@/components/m2/Toast";
import { api } from "@/lib/api";

export default function ConfigurablePage(){
  const [parentSku, setParentSku] = useState("TEST-CFG");
  const [childSku, setChildSku] = useState("TEST-BLUE-EXTRA");
  const [attrCode, setAttrCode] = useState("cfg_color");
  const [valueIndex, setValueIndex] = useState("7");
  const [toast, setToast] = useState<{k:"success"|"error"|"info"|"warn"; m:string}|null>(null);
  const [log, setLog] = useState("");

  const link = async ()=>{
    setLog("⏳ sender…");
    try{
      const body = { parentSku, childSku, attrCode, valueIndex: Number(valueIndex) };
      const data = await api.post("/ops/configurable/link", body);
      setLog(JSON.stringify(data, null, 2));
      setToast({k:"success", m: data?.linked ? "Linket" : "OK"});
    }catch(e:any){
      setToast({k:"error", m:e?.message||"Feil"});
      setLog("❌ " + (e?.message||String(e)));
    }
  };

  return (
    <div className="p-6 space-y-4">
      <div className="grid gap-3 max-w-lg">
        <label className="block">
          <div className="text-sm">Parent SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={parentSku} onChange={e=>setParentSku(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Child SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={childSku} onChange={e=>setChildSku(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Attributt (attrCode)</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={attrCode} onChange={e=>setAttrCode(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Value index</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={valueIndex} onChange={e=>setValueIndex(e.target.value)} />
        </label>

        <button onClick={link} className="px-3 py-2 rounded-lg border hover:bg-black/5">Link child → parent</button>

        {toast && <Toast kind={toast.k} msg={toast.m} onDone={()=>setToast(null)} />}
        <pre className="text-xs bg-black/5 p-3 rounded max-h-64 overflow-auto">{log}</pre>
      </div>
    </div>
  );
}
