"use client";
import { useEffect, useState } from "react";

type Addr = {
  id: string; label?: string; name: string; phone?: string;
  line1: string; line2?: string; zip: string; city: string; country: string;
  isDefault?: boolean;
};

const CUSTOMER_ID = "demo-user";

export default function AddressesPage() {
  const [items, setItems] = useState<Addr[]>([]);
  const [form, setForm] = useState<Partial<Addr>>({
    name: "Fornavn Etternavn", line1: "", zip: "", city: "", country: "NO",
  });

  async function load() {
    const r = await fetch("/api/customers/" + CUSTOMER_ID + "/addresses");
    const j = await r.json(); setItems(j.items || []);
  }
  useEffect(() => { load(); }, []);

  async function save() {
    if (!form?.name || !form?.line1 || !form?.zip || !form?.city || !form?.country) return;
    await fetch("/api/customers/" + CUSTOMER_ID + "/addresses", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(form)
    });
    setForm({ name: "Fornavn Etternavn", line1: "", zip: "", city: "", country: "NO" });
    load();
  }
  async function setDefault(id: string) {
    await fetch("/api/customers/" + CUSTOMER_ID + "/addresses/" + id, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ isDefault: true }) });
    load();
  }
  async function remove(id: string) {
    await fetch("/api/customers/" + CUSTOMER_ID + "/addresses/" + id, { method: "DELETE" });
    load();
  }

  return (
    <div className="p-6 space-y-6">
      <h1 className="text-2xl font-bold">🏠 Mine adresser</h1>

      <div className="grid gap-3 max-w-xl">
        <div className="grid grid-cols-2 gap-2">
          <input className="border rounded px-3 py-2" placeholder="Navn" value={form.name||""} onChange={e=>setForm(v=>({ ...v, name:e.target.value }))}/>
          <input className="border rounded px-3 py-2" placeholder="Telefon" value={form.phone||""} onChange={e=>setForm(v=>({ ...v, phone:e.target.value }))}/>
          <input className="border rounded px-3 py-2 col-span-2" placeholder="Adresse (linje 1)" value={form.line1||""} onChange={e=>setForm(v=>({ ...v, line1:e.target.value }))}/>
          <input className="border rounded px-3 py-2 col-span-2" placeholder="Adresse (linje 2)" value={form.line2||""} onChange={e=>setForm(v=>({ ...v, line2:e.target.value }))}/>
          <input className="border rounded px-3 py-2" placeholder="Postnr" value={form.zip||""} onChange={e=>setForm(v=>({ ...v, zip:e.target.value }))}/>
          <input className="border rounded px-3 py-2" placeholder="Sted" value={form.city||""} onChange={e=>setForm(v=>({ ...v, city:e.target.value }))}/>
          <input className="border rounded px-3 py-2 col-span-2" placeholder="Land" value={form.country||"NO"} onChange={e=>setForm(v=>({ ...v, country:e.target.value }))}/>
        </div>
        <label className="inline-flex items-center gap-2">
          <input type="checkbox" checked={!!form.isDefault} onChange={e=>setForm(v=>({ ...v, isDefault: e.target.checked }))}/>
          <span>Sett som standard</span>
        </label>
        <button onClick={save} className="px-3 py-2 rounded-lg border hover:bg-black/5">➕ Lagre adresse</button>
      </div>

      <div className="grid gap-3 max-w-xl">
        {items.map(a=>(
          <div key={a.id} className="border rounded p-3 flex items-center justify-between">
            <div>
              <div className="font-medium">{a.name} {a.isDefault ? <span className="ml-2 text-xs px-2 py-0.5 border rounded">default</span> : null}</div>
              <div className="text-sm opacity-80">
                {a.line1}{a.line2 ? ", " + a.line2 : ""}, {a.zip} {a.city}, {a.country}{a.phone ? " • " + a.phone : ""}
              </div>
              {a.label && <div className="text-xs opacity-60">{a.label}</div>}
            </div>
            <div className="flex gap-2">
              {!a.isDefault && <button onClick={()=>setDefault(a.id)} className="px-2 py-1 rounded border">Gjør til standard</button>}
              <button onClick={()=>remove(a.id)} className="px-2 py-1 rounded border">Slett</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
