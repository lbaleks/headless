"use client";
import React from "react";

type VariantInfo = { label: string; multiplier: number; price: number; maxUnits: number };
type ConfigInfo = { sku: string; name?: string; strategy?: "FIFO" | "FEFO" };

const SKUS = ["FLOUR-001", "COFFEE-250"]; // demo

async function safeJson(r: Response) {
  try {
    return await r.json();
  } catch {
    // Returnér noe tomt for å unngå runtime-krasj hvis server svarer HTML/empty
    return null;
  }
}

async function fetchVariants(sku:string): Promise<VariantInfo[]> {
  try {
    const r = await fetch(`/api/catalog/product/${encodeURIComponent(sku)}/variants`, { cache: "no-store" });
    if (!r.ok) return [];
    const j = await safeJson(r);
    return Array.isArray(j?.variants) ? (j.variants as VariantInfo[]) : [];
  } catch {
    return [];
  }
}

async function fetchConfig(sku:string): Promise<ConfigInfo> {
  try {
    const r = await fetch(`/api/catalog/product/${encodeURIComponent(sku)}/config`, { cache: "no-store" });
    if (!r.ok) return { sku, name: sku, strategy: "FEFO" };
    const j = await safeJson(r);
    if (!j || typeof j !== "object") return { sku, name: sku, strategy: "FEFO" };
    return { sku, name: j.name || sku, strategy: (j.strategy === "FIFO" ? "FIFO" : "FEFO") };
  } catch {
    return { sku, name: sku, strategy: "FEFO" };
  }
}

async function saveStrategy(sku:string, strategy:"FIFO"|"FEFO") {
  try {
    const r = await fetch(`/api/catalog/product/${encodeURIComponent(sku)}/config`, {
      method:"PATCH",
      headers:{ "Content-Type":"application/json" },
      body: JSON.stringify({ strategy })
    });
    const j = await safeJson(r);
    return j ?? { ok:false };
  } catch {
    return { ok:false };
  }
}

export default function ProductsOverview() {
  const [rows, setRows] = React.useState<{ sku: string; name: string; strategy: "FIFO"|"FEFO"; variants: VariantInfo[] }[]>([]);
  const [loading, setLoading] = React.useState(true);
  const [busy, setBusy] = React.useState<string|null>(null);

  React.useEffect(() => {
    let alive = true;
    (async () => {
      const out: typeof rows = [];
      for (const sku of SKUS) {
        const [variants, cfg] = await Promise.all([fetchVariants(sku), fetchConfig(sku)]);
        out.push({ sku, name: cfg?.name || sku, strategy: (cfg?.strategy as any) || "FEFO", variants });
      }
      if (alive) { setRows(out); setLoading(false); }
    })();
    return () => { alive = false; };
  }, []);

  const updateRow = (sku:string, patch: Partial<(typeof rows)[number]>) =>
    setRows(cur => cur.map(r => r.sku===sku ? { ...r, ...patch } : r));

  const onSave = async (sku:string) => {
    const row = rows.find(r=>r.sku===sku); if(!row) return;
    setBusy(sku);
    await saveStrategy(sku, row.strategy);
    setBusy(null);
  };

  return (
    <main className="space-y-6 p-6">
      <h2 className="text-base font-medium">Products → Overview</h2>
      <section className="card">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-xs opacity-60">
              <tr>
                <th className="py-1.5 pr-3">SKU</th>
                <th className="py-1.5 pr-3">Navn</th>
                <th className="py-1.5 pr-3">Strategi</th>
                <th className="py-1.5 pr-3">Varianter (pris / maks antall)</th>
                <th className="py-1.5 pr-3"></th>
              </tr>
            </thead>
            <tbody>
              {loading && <tr><td className="py-2 sub" colSpan={5}>Laster…</td></tr>}
              {!loading && rows.length===0 && <tr><td className="py-2 sub" colSpan={5}>Ingen produkter</td></tr>}
              {!loading && rows.map((r) => (
                <tr key={r.sku} className="border-t">
                  <td className="py-1.5 pr-3">{r.sku}</td>
                  <td className="py-1.5 pr-3">{r.name}</td>
                  <td className="py-1.5 pr-3">
                    <select
                      className="border rounded-lg px-2 py-1 text-sm"
                      value={r.strategy}
                      onChange={e=>updateRow(r.sku, { strategy: e.target.value as "FIFO"|"FEFO" })}
                    >
                      <option value="FEFO">FEFO (kortest utløp først)</option>
                      <option value="FIFO">FIFO (først inn først ut)</option>
                    </select>
                  </td>
                  <td className="py-1.5 pr-3">
                    <div className="flex flex-wrap gap-2">
                      {r.variants.slice(0,4).map(v => (
                        <span key={v.label} className="px-2 py-0.5 rounded border text-xs bg-slate-50">
                          {v.label}: <b>{v.price}</b> / maks {v.maxUnits}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="py-1.5 pr-3">
                    <button className="btn" disabled={busy===r.sku} onClick={()=>onSave(r.sku)}>
                      {busy===r.sku ? "Lagrer…" : "Lagre"}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}
