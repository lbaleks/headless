"use client";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";

type AclItem = { check: string; requires: string; authorized: boolean|null; status: number; note: string; };
type AclResp = { ok: boolean; summary: AclItem[]; missing: string[]; unknown: AclItem[]; };

export default function VariantsPage() {
  const [parentSku, setParentSku] = useState("TEST-CFG");
  const [sku, setSku] = useState("TEST-BLUE-EXTRA");
  const [cfgAttr, setCfgAttr] = useState("cfg_color");
  const [cfgValue, setCfgValue] = useState("7");
  const [label, setLabel] = useState("Blue");
  const [qty, setQty] = useState("5");
  const [stockEnabled, setStockEnabled] = useState(true);

  const [log, setLog] = useState<string>("");
  const [acl, setAcl] = useState<AclResp | null>(null);
  const [loadingAcl, setLoadingAcl] = useState(false);

  const gateway = useMemo(() => {
    return process.env.NEXT_PUBLIC_GATEWAY_BASE || process.env.NEXT_PUBLIC_GATEWAY || "http://localhost:3044";
  }, []);

  const refreshAcl = async () => {
    setLoadingAcl(true);
    setLog(l => l + (l ? "\n" : "") + "⏳ Henter ACL-status…");
    try {
      const data = await api.get("/ops/acl/check");
      setAcl(data as AclResp);
      setLog(l => l + "\n✅ ACL-status oppdatert.");
    } catch (e:any) {
      setLog(l => l + "\n❌ Klarte ikke hente ACL: " + e.message);
    } finally {
      setLoadingAcl(false);
    }
  };

  useEffect(() => { refreshAcl(); }, []);

  const heal = async () => {
    setLog("⏳ Sender heal…");
    try {
      const body: any = {
        parentSku,
        sku,
        cfgAttr,
        cfgValue: Number(cfgValue),
        label,
        websiteId: 1,
      };
      if (stockEnabled) {
        body.stock = { source_code: "default", quantity: Number(qty), status: 1 };
      }
      const data = await api.post("/ops/variant/heal", body);
      setLog((JSON.stringify(data, null, 2)));
    } catch (e: any) {
      setLog("❌ " + e.message);
    }
  };

  const aclBadge = (a: boolean|null) => {
    if (a === true) return <span className="px-2 py-0.5 rounded bg-green-100 text-green-800 text-xs">authorized</span>;
    if (a === false) return <span className="px-2 py-0.5 rounded bg-red-100 text-red-800 text-xs">forbidden</span>;
    return <span className="px-2 py-0.5 rounded bg-yellow-100 text-yellow-800 text-xs">unknown</span>;
  };

  return (
    <div className="p-6 space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">🧩 Variant-healer</h1>
        <div className="text-sm text-gray-500">Gateway: <code>{gateway}</code></div>
      </div>

      <div className="flex gap-2">
        <Link href="/m2" className="px-3 py-2 rounded-lg border hover:bg-black/5">← Hjem</Link>
        <button onClick={refreshAcl} disabled={loadingAcl} className="px-3 py-2 rounded-lg border hover:bg-black/5">
          {loadingAcl ? "Oppdaterer…" : "↻ Oppdater ACL"}
        </button>
      </div>

      {/* ACL panel */}
      <div className="grid gap-2">
        <div className="font-medium">ACL-status</div>
        {!acl && <div className="text-sm text-gray-500">Henter…</div>}
        {acl && (
          <div className="overflow-hidden rounded-lg border">
            <table className="w-full text-sm">
              <thead className="bg-gray-50">
                <tr>
                  <th className="text-left p-2">Check</th>
                  <th className="text-left p-2">Requires</th>
                  <th className="text-left p-2">Auth</th>
                  <th className="text-left p-2">HTTP</th>
                  <th className="text-left p-2">Note</th>
                </tr>
              </thead>
              <tbody>
                {acl.summary.map((row, i) => (
                  <tr key={i} className="border-t">
                    <td className="p-2">{row.check}</td>
                    <td className="p-2">{row.requires}</td>
                    <td className="p-2">{aclBadge(row.authorized)}</td>
                    <td className="p-2">{row.status}</td>
                    <td className="p-2">{row.note}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Heal form */}
      <div className="grid gap-3 max-w-xl">
        <label className="block">
          <div className="text-sm">Parent SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={parentSku} onChange={e=>setParentSku(e.target.value)} />
        </label>
        <label className="block">
          <div className="text-sm">Variant SKU</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={sku} onChange={e=>setSku(e.target.value)} />
        </label>
        <div className="grid grid-cols-2 gap-3">
          <label className="block">
            <div className="text-sm">Attributt</div>
            <input className="border rounded-lg px-3 py-2 w-full" value={cfgAttr} onChange={e=>setCfgAttr(e.target.value)} />
          </label>
          <label className="block">
            <div className="text-sm">Verdi (ID)</div>
            <input className="border rounded-lg px-3 py-2 w-full" value={cfgValue} onChange={e=>setCfgValue(e.target.value)} />
          </label>
        </div>
        <label className="block">
          <div className="text-sm">Label</div>
          <input className="border rounded-lg px-3 py-2 w-full" value={label} onChange={e=>setLabel(e.target.value)} />
        </label>

        <div className="flex items-center gap-3">
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={stockEnabled} onChange={e=>setStockEnabled(e.target.checked)} />
            <span className="text-sm">Oppdater stock</span>
          </label>
          {stockEnabled && (
            <label className="flex items-center gap-2">
              <span className="text-sm">Qty</span>
              <input className="border rounded-lg px-2 py-1 w-24" value={qty} onChange={e=>setQty(e.target.value)} />
            </label>
          )}
        </div>

        <button onClick={heal} className="px-3 py-2 rounded-lg border hover:bg-black/5">
          Heal / opprett variant
        </button>

        <pre className="text-xs bg-black/5 p-3 rounded max-h-72 overflow-auto whitespace-pre-wrap">{log}</pre>
      </div>
    </div>
  );
}
