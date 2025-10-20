"use client";
import { useEffect, useMemo, useState } from "react";

type Check = { label: string; ok: boolean; ms?: number; note?: string; status?: number };
const GW = process.env.NEXT_PUBLIC_GATEWAY_BASE || "http://localhost:3044";

async function ping(url: string, opts: RequestInit = {}, label="") : Promise<Check> {
  const ctrl = new AbortController();
  const t = setTimeout(()=>ctrl.abort(), 4000);
  const t0 = (typeof performance !== "undefined" ? performance.now() : Date.now());
  try {
    const r = await fetch(url, { ...opts, signal: ctrl.signal, cache: "no-store" });
    let note = "";
    try { const j = await r.clone().json(); note = (j && (j.note || j.message)) || ""; } catch {}
    const t1 = (typeof performance !== "undefined" ? performance.now() : Date.now());
    const ms = Math.max(0, Math.round(t1 - t0));
    return { label, ok: r.ok, ms, note: note || r.statusText, status: r.status };
  } catch (e:any) {
    const t1 = (typeof performance !== "undefined" ? performance.now() : Date.now());
    const ms = Math.max(0, Math.round(t1 - t0));
    return { label, ok:false, ms, note: (e && (e.name==="AbortError"?"timeout":e.message)) || "fetch_failed" };
  } finally { clearTimeout(t); }
}

export default function AdminStatus() {
  const [items, setItems] = useState<Check[]|null>(null);
  const [fetching, setFetching] = useState(false);

  async function run() {
    setFetching(true);
    const checks: Check[] = await Promise.all([
      ping(`${GW}/health/magento`, {}, "Magento health"),
      ping(`${GW}/ops/acl/check`, {}, "ACL check"),
    ]);
    setItems(checks);
    setFetching(false);
  }

  useEffect(() => { run(); }, []);
  const allOk = useMemo(()=> items?.every(i=>i.ok) ?? false, [items]);

  return (
    <div className="rounded-lg border p-3 bg-black/5 dark:bg-white/5">
      <div className="flex flex-wrap items-center gap-2 justify-between">
        <div className="flex items-center gap-2">
          <span className="font-semibold">Status</span>
          <span className={`px-2 py-0.5 rounded text-xs ${allOk ? "bg-green-600/10 text-green-700 dark:text-green-300" : "bg-amber-600/10 text-amber-700 dark:text-amber-300"}`}>
            {allOk ? "OK" : "Krever oppmerksomhet"}
          </span>
        </div>
        <div className="text-xs opacity-70">G/W: <code>{GW}</code></div>
      </div>

      <div className="mt-2 grid sm:grid-cols-2 gap-2">
        {(items||[]).map((c, i)=>(
          <div key={i} className={`rounded border px-2 py-1 text-sm flex items-center justify-between ${c.ok ? "border-green-600/30" : "border-red-600/30"}`}>
            <div className="flex items-center gap-2">
              <span className={`w-2 h-2 rounded-full ${c.ok ? "bg-green-500" : "bg-red-500"}`}></span>
              <span>{c.label}</span>
            </div>
            <div className="text-xs opacity-70">{c.ms ?? "–"} ms</div>
          </div>
        ))}
      </div>

      <div className="mt-2 flex gap-2">
        <button
          className="px-3 py-1 rounded border hover:bg-black/10 dark:hover:bg-white/10 text-sm"
          onClick={run}
          disabled={fetching}
        >
          {fetching ? "Oppdaterer…" : "Oppdater"}
        </button>
      </div>
    </div>
  );
}
