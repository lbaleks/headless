"use client";
import React from "react";
import Link from "next/link";
type Row = { id:string; name:string; priceTier?: "A"|"B"|"C"; role?: "admin"|"ops"|"support"|"viewer" };

async function j(url:string, init?:RequestInit){
  const r = await fetch(url, { cache:"no-store", ...init });
  const t = await r.text(); if(!t) return {};
  try{ return JSON.parse(t); } catch{ return {}; }
}

export default function CompaniesPage(){
  const [rows,setRows] = React.useState<Row[]>([]);
  const [loading,setLoading] = React.useState(true);
  const [form,setForm] = React.useState<Row>({ id:"", name:"", priceTier:"A", role:"viewer" });

  const load = React.useCallback(async()=>{
    setLoading(true);
    try {
      const data:any = await j("/api/companies");
      setRows(Array.isArray(data?.companies)? data.companies : []);
    } finally { setLoading(false); }
  },[]);
  React.useEffect(()=>{ load(); }, [load]);

  const save = async ()=>{
    await fetch("/api/companies",{ method:"POST", headers:{ "Content-Type":"application/json" }, body: JSON.stringify(form) });
    setForm({ id:"", name:"", priceTier:"A", role:"viewer" }); load();
  };

  return (
    <main className="space-y-6 p-6">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-medium">Companies</h2>
        <Link href="/admin/users">Users</Link>
      </div>

      <section className="card space-y-3">
        <div className="grid grid-cols-1 sm:grid-cols-5 gap-3 items-end">
          <label className="block"><div className="sub mb-1">ID</div>
            <input className="border rounded px-2 py-1 w-full" value={form.id} onChange={e=>setForm({...form, id:e.target.value})}/>
          </label>
          <label className="block"><div className="sub mb-1">Navn</div>
            <input className="border rounded px-2 py-1 w-full" value={form.name} onChange={e=>setForm({...form, name:e.target.value})}/>
          </label>
          <label className="block"><div className="sub mb-1">Prisnivå</div>
            <select className="border rounded px-2 py-1 w-full" value={form.priceTier||"A"} onChange={e=>setForm({...form, priceTier:(e.target.value as any)})}>
              <option value="A">A</option><option value="B">B</option><option value="C">C</option>
            </select>
          </label>
          <label className="block"><div className="sub mb-1">Standardrolle</div>
            <select className="border rounded px-2 py-1 w-full" value={form.role||"viewer"} onChange={e=>setForm({...form, role:(e.target.value as any)})}>
              <option value="admin">admin</option><option value="ops">ops</option><option value="support">support</option><option value="viewer">viewer</option>
            </select>
          </label>
          <button className="btn" onClick={save}>Legg til / oppdater</button>
        </div>
      </section>

      <section className="card">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-xs opacity-60">
              <tr><th className="py-1.5 pr-3">ID</th><th className="py-1.5 pr-3">Navn</th><th className="py-1.5 pr-3">Prisnivå</th><th className="py-1.5 pr-3">Standardrolle</th></tr>
            </thead>
            <tbody>
              {loading && <tr><td className="py-2 sub" colSpan={4}>Laster…</td></tr>}
              {!loading && rows.length===0 && <tr><td className="py-2 sub" colSpan={4}>Ingen selskaper</td></tr>}
              {rows.map(r=>(
                <tr key={r.id} className="border-t">
                  <td className="py-1.5 pr-3">{r.id}</td>
                  <td className="py-1.5 pr-3">{r.name}</td>
                  <td className="py-1.5 pr-3">{r.priceTier||"—"}</td>
                  <td className="py-1.5 pr-3">{r.role||"—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}
