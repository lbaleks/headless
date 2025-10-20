"use client";
import { useState } from "react"

export default function AttributeEditor({ sku, initial }: { sku:string, initial:any }) {
  const [attrs, setAttrs] = useState<any>(initial || {})
  const [saving, setSaving] = useState(false)

  async function save() {
    setSaving(true)
    const res = await fetch("/api/products/update-attributes", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ sku, attributes: attrs }),
    })
    setSaving(false)
    if (res.ok) alert("✅ Lagret!")
    else alert("❌ Feil ved lagring")
  }

  return (
    <div className="p-4 border rounded-md mt-4 space-y-2 bg-white shadow-sm">
      <h3 className="font-semibold">Attribute Editor</h3>
      {["ibu","hops","image"].map((key) => (
        <div key={key} className="flex items-center gap-2">
          <label className="w-20 text-sm">{key}</label>
          <input
            className="border p-1 rounded flex-1"
            value={attrs[key] ?? ""}
            onChange={(e) => setAttrs({ ...attrs, [key]: e.target.value })}
          />
        </div>
      ))}
      <button
        disabled={saving}
        onClick={save}
        className="px-3 py-1 bg-blue-600 text-white rounded-md text-sm"
      >
        {saving ? "Lagrer..." : "Lagre"}
      </button>
    </div>
  )
}
