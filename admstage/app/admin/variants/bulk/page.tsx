"use client";
import { useMemo, useState } from "react";
import AdminStatus from "../../../components/AdminStatus";

type Row = {
  parentSku: string;
  childSku: string;
  attrCode: string;
  valueIndex: number;
  price?: number;
  stock?: number;
  status?: "pending" | "ok" | "error";
  note?: string;
};

const GW: string = (process.env.NEXT_PUBLIC_GATEWAY_BASE as string) || "http://localhost:3044";
function gw(path: string) { return (GW || "").replace(/\/$/, "") + path; }

function parseCSV(txt: string): Row[] {
  const clean = txt.trim().replace(/\r/g, "");
  if (!clean) return [];
  // Autodetect ; vs ,
  const delim = (clean.split("\n")[0] || "").includes(";") ? ";" : ",";
  const lines = clean.split("\n").filter(Boolean);
  // Support header or no header
  const hasHeader = /parentSku/i.test(lines[0]);
  const rows = (hasHeader ? lines.slice(1) : lines).map((ln) => {
    const c = ln.split(delim).map((x) => x.trim());
    const [parentSku, childSku, attrCode, valueIndex, price, stock] = c;
    return {
      parentSku,
      childSku,
      attrCode,
      valueIndex: Number(valueIndex),
      price: price ? Number(price) : undefined,
      stock: stock ? Number(stock) : undefined,
      status: "pending",
    } as Row;
  });
  return rows.filter(r => r.parentSku && r.childSku && r.attrCode && Number.isFinite(r.valueIndex));
}

export default function BulkVariants() {
  const [raw, setRaw] = useState<string>("parentSku,childSku,attrCode,valueIndex,price,stock\nTEST-CFG,TEST-BLUE-EXTRA,cfg_color,7,199,13");
  const [rows, setRows] = useState<Row[]>([]);
  const [busy, setBusy] = useState(false);
  const any = useMemo(() => rows.length > 0, [rows]);

  function loadFromText() {
    const parsed = parseCSV(raw);
    setRows(parsed);
  }

  async function linkConfigurable(r: Row) {
    const res = await fetch(gw("/ops/configurable/link"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        parentSku: r.parentSku,
        childSku: r.childSku,
        attrCode: r.attrCode,
        valueIndex: r.valueIndex,
      }),
    });
    let j: any = null;
    try { j = await res.json(); } catch { /* ignore */ }
    if (!res.ok || !j?.ok) throw new Error(j?.error || "link_failed");
    return j;
  }

  async function upsertPrice(r: Row) {
    if (typeof r.price !== "number") return { ok: true, skipped: true };
    const res = await fetch(gw("/ops/price/upsert"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sku: r.childSku, price: r.price }),
    });
    let j: any = null;
    try { j = await res.json(); } catch { /* ignore */ }
    if (!res.ok || !j?.ok) throw new Error(j?.error || "price_failed");
    return j;
  }

  async function healVariant(r: Row) {
    // Optional — ikke alle gateways har dette; ignorer feil
    try {
      const res = await fetch(gw("/ops/variant/heal"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ parentSku: r.parentSku }),
      });
      let j: any = null;
      try { j = await res.json(); } catch { /* ignore */ }
      return j?.ok ? j : { ok: false, skipped: true };
    } catch { return { ok: false, skipped: true }; }
  }

  async function syncOne(idx: number) {
    setRows((cur) => cur.map((r, i) => (i === idx ? { ...r, status: "pending", note: "…" } : r)));
    const r = rows[idx];
    
    try {
      await linkConfigurable(r);
      await upsertPrice(r);
      await healVariant(r);
      setRows((cur) => cur.map((x, i) => (i === idx ? { ...x, status: "ok", note: "OK" } : x)));
    } catch (e: any) {
      setRows((cur) => cur.map((x, i) => (i === idx ? { ...x, status: "error", note: e?.message || "feil" } : x)));
    }
    
  }

  async function syncAll() {
    setBusy(true);
    for (let i = 0; i < rows.length; i++) {
       
      await syncOne(i);
    }
    setBusy(false);
  }

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">🧩 Bulk-varianten</h1>
      <AdminStatus />

      <div className="grid gap-3">
        <label className="block">
          <div className="text-sm mb-1 opacity-70">CSV/klipp-og-lim (delim: komma eller semikolon)</div>
          <textarea
            className="w-full border rounded p-2 font-mono text-xs min-h-40"
            value={raw}
            onChange={(e) => setRaw(e.target.value)}
            spellCheck={false}
            placeholder="parentSku,childSku,attrCode,valueIndex,price,stock"
          />
        </label>
        <div className="flex gap-2">
          <button className="px-3 py-2 rounded border hover:bg-black/5" onClick={loadFromText}>Parse</button>
          <button className="px-3 py-2 rounded border hover:bg-black/5 disabled:opacity-50" disabled={!any || busy} onClick={syncAll}>
            {busy ? "Synker…" : "Sync alle"}
          </button>
        </div>
      </div>

      {!any && <div className="opacity-70">Ingen rader ennå. Lim inn CSV og trykk Parse.</div>}

      {any && (
        <div className="overflow-x-auto">
          <table className="min-w-[720px] w-full border rounded">
            <thead className="bg-black/5 dark:bg-white/5 text-sm">
              <tr>
                <th className="text-left p-2">Parent</th>
                <th className="text-left p-2">Child</th>
                <th className="text-left p-2">Attr</th>
                <th className="text-left p-2">Index</th>
                <th className="text-left p-2">Pris</th>
                <th className="text-left p-2">Lager</th>
                <th className="text-left p-2">Status</th>
                <th className="text-left p-2">Aksjon</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {rows.map((r, i) => (
                <tr key={i} className="align-top">
                  <td className="p-2 text-sm">{r.parentSku}</td>
                  <td className="p-2 text-sm">{r.childSku}</td>
                  <td className="p-2 text-sm">{r.attrCode}</td>
                  <td className="p-2 text-sm">{r.valueIndex}</td>
                  <td className="p-2 text-sm">{typeof r.price === "number" ? r.price.toFixed(2) : <span className="opacity-50">–</span>}</td>
                  <td className="p-2 text-sm">{typeof r.stock === "number" ? r.stock : <span className="opacity-50">–</span>}</td>
                  <td className="p-2 text-sm">
                    {r.status === "ok" && <span className="px-2 py-1 rounded bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-300">OK</span>}
                    {r.status === "error" && <span className="px-2 py-1 rounded bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-300" title={r.note}>Feil</span>}
                    {(!r.status || r.status === "pending") && <span className="px-2 py-1 rounded bg-amber-100 text-amber-800 dark:bg-amber-900/20 dark:text-amber-300">{r.note || "Klar"}</span>}
                  </td>
                  <td className="p-2">
                    <button className="px-3 py-1 rounded border hover:bg-black/5 text-sm disabled:opacity-50" disabled={busy} onClick={() => syncOne(i)}>Sync</button>
                    {r.note && <div className="text-[11px] opacity-70 mt-1 max-w-[24ch] line-clamp-2">{r.note}</div>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
