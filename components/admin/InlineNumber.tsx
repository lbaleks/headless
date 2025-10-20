"use client";
import { useState } from "react";
export function InlineNumber({ value,onSave,step=1,min=0 }:{
  value?:number; onSave:(v:number)=>Promise<void>; step?:number; min?:number;
}) {
  const [v,setV]=useState<number>(Number(value??0)); const [saving,setSaving]=useState(false);
  async function commit(){ if(saving)return; setSaving(true); try{await onSave(Number(v));}finally{setSaving(false);} }
  return (
    <div className="inline-flex items-center gap-2">
      <input type="number" step={step} min={min} className="border rounded px-2 py-1 w-28 text-sm bg-white"
        value={v} onChange={e=>setV(Number(e.target.value))}
        onBlur={commit} onKeyDown={e=>{if(e.key==="Enter")(e.target as HTMLInputElement).blur();}}/>
      {saving && <span className="text-xs text-neutral-500">lagrer…</span>}
    </div>
  );
}
