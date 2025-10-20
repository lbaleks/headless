"use client";
import { useState } from "react";
export function InlineText({ value, onSave, placeholder="—", className="" }:{
  value?: string; onSave:(v:string)=>Promise<void>; placeholder?:string; className?:string;
}) {
  const [v,setV]=useState(value??""); const [saving,setSaving]=useState(false);
  async function commit(){ if(saving)return; setSaving(true); try{await onSave(v);}finally{setSaving(false);} }
  return (
    <div className={`inline-flex items-center gap-2 ${className}`}>
      <input className="border rounded px-2 py-1 text-sm bg-white" value={v}
        onChange={e=>setV(e.target.value)} placeholder={placeholder}
        onBlur={commit} onKeyDown={e=>{if(e.key==="Enter")(e.target as HTMLInputElement).blur();}}/>
      {saving && <span className="text-xs text-neutral-500">lagrer…</span>}
    </div>
  );
}
