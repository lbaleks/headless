"use client";
import React from "react";
import { getRole, setRole, type Role } from "../../lib/rbac";

export default function RoleBadge(){
  const [role,set] = React.useState<Role>("admin");
  const [open,setOpen] = React.useState(false);
  React.useEffect(()=>{ getRole().then(set); },[]);
  const apply = async (r:Role)=>{ await setRole(r); set(r); };

  return (
    <div className="relative flex items-center gap-2">
      <span className="px-2 py-0.5 rounded border text-xs bg-slate-50">Role: <b>{role}</b></span>
      <button className="btn" onClick={()=>setOpen(v=>!v)}>Bytt</button>
      {open && (
        <div className="absolute top-full mt-2 z-20 bg-white border rounded shadow p-2 text-sm">
          {(["admin","ops","support","viewer"] as Role[]).map(r=>(
            <button key={r} className="btn mr-1 mb-1" onClick={()=>apply(r)}>{r}</button>
          ))}
        </div>
      )}
    </div>
  );
}
