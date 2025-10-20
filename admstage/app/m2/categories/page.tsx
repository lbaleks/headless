"use client";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { api } from "@/lib/api";

export default function CategoryEditPage() {
  const sp = useSearchParams();
  const sku = sp.get("sku") || "";
  const preset = sp.get("cats") || "";
  const [cats, setCats] = useState(preset);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<string>("");

  useEffect(() => { setCats(preset); }, [preset]);

  const parsed = useMemo(() => {
    return cats
      .split(/[,\s;]+/)
      .map(s => s.trim())
      .filter(Boolean)
      .filter(s => /^[0-9]+$/.test(s))
      .map(s => Number(s));
  }, [cats]);

  const save = async () => {
    setSaving(true); setMsg("");
    try {
      if (!sku) throw new Error("Mangler SKU");
      const body = { items: [{ sku, categoryIds: parsed }] };
      const res = await api.post("/ops/category/replace", body);
      if (res?.ok) setMsg("✅ Lagret!");
      else throw new Error(res?.error || "Ukjent feil");
    } catch (e:any) {
      setMsg(`❌ ${e.message || e}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">🗂 Category mapper</h1>
      <div className="flex items-center gap-2">
        <Link className="px-3 py-2 rounded-lg border hover:bg-black/5" href="/m2/products">← Produkter</Link>
        <Link className="px-3 py-2 rounded-lg border hover:bg-black/5" href="/m2">Hjem</Link>
      </div>

      <div className="p-4 rounded-xl border space-y-3 max-w-xl">
        <div className="text-sm text-gray-600">SKU</div>
        <input className="border rounded-lg px-3 py-2 w-full font-mono bg-black/5" value={sku} readOnly />

        <div className="text-sm text-gray-600">Category IDs (komma-separert)</div>
        <input
          className="border rounded-lg px-3 py-2 w-full"
          placeholder="f.eks 2,4,7"
          value={cats}
          onChange={(e)=>setCats(e.target.value)}
        />

        <div className="text-xs text-gray-500">
          Parser til: [{parsed.join(", ")}]
        </div>

        <button className="px-3 py-2 rounded-lg border hover:bg-black/5" onClick={save} disabled={saving}>
          {saving ? "Lagrer…" : "Lagre (replace)"}
        </button>

        {msg && <div className="text-sm">{msg}</div>}
      </div>
    </div>
  );
}
