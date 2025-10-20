"use client";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";

type M2Product = {
  sku: string;
  name: string;
  price: number;
  status: number;
  visibility: number;
  extension_attributes?: { category_links?: { category_id: string }[] };
};

export default function ProductsPage() {
  const [q, setQ] = useState("TEST");
  const [rows, setRows] = useState<M2Product[]>([]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState("");

  const load = async () => {
    setLoading(true); setErr("");
    try {
      const params = new URLSearchParams({ q, page: "1", size: "50" });
      const data = await api.get(`/ops/products/list?${params.toString()}`);
      setRows(data?.items ?? []);
    } catch (e:any) { setErr(e.message || "Feil"); }
    finally { setLoading(false); }
  };

  useEffect(() => { load();   }, []);

  const items = useMemo(() => rows ?? [], [rows]);

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">📦 Produkter</h1>

      <div className="flex gap-2">
        <input
          className="border rounded-lg px-3 py-2 w-80"
          placeholder="Søk (sku/navn)…"
          value={q}
          onChange={(e)=>setQ(e.target.value)}
          onKeyDown={(e)=>{ if (e.key==="Enter") load(); }}
        />
        <button className="px-3 py-2 rounded-lg border hover:bg-black/5" onClick={load} disabled={loading}>
          {loading ? "Søker…" : "Søk"}
        </button>
        <Link className="px-3 py-2 rounded-lg border hover:bg-black/5" href="/m2">← Tilbake</Link>
      </div>

      {err && <div className="text-red-600 text-sm">{err}</div>}

      <div className="overflow-x-auto border rounded-xl">
        <table className="min-w-full text-sm">
          <thead className="bg-black/5">
            <tr>
              <th className="text-left p-2">SKU</th>
              <th className="text-left p-2">Navn</th>
              <th className="text-right p-2">Pris</th>
              <th className="text-left p-2">Vis</th>
              <th className="text-left p-2">Cats</th>
              <th className="text-left p-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {items.map(p => {
              const cats = p.extension_attributes?.category_links?.map(c=>c.category_id).join(",") || "";
              return (
                <tr key={p.sku} className="border-t">
                  <td className="p-2 font-mono">{p.sku}</td>
                  <td className="p-2">{p.name}</td>
                  <td className="p-2 text-right">{p.price}</td>
                  <td className="p-2">{p.visibility}</td>
                  <td className="p-2">{cats || <span className="text-gray-400">–</span>}</td>
                  <td className="p-2">
                    <Link className="px-2 py-1 rounded border hover:bg-black/5"
                      href={`/m2/categories?sku=${encodeURIComponent(p.sku)}&cats=${encodeURIComponent(cats)}`}>
                      Map categories
                    </Link>
                  </td>
                </tr>
              );
            })}
            {!items.length && (
              <tr><td className="p-4 text-gray-500" colSpan={6}>Ingen treff.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
