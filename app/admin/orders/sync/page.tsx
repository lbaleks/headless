"use client";
// app/admin/orders/sync/page.tsx
import React from "react";
import Link from "next/link";

type Row = { id: string; status: string; updatedAt: number; msg?: string; selected?: boolean };

function statusChip(status: string) {
  if (status === "error") return "bg-rose-50 border-rose-200";
  if (status === "queued") return "bg-amber-50 border-amber-200";
  if (status === "exported") return "bg-emerald-50 border-emerald-200";
  return "bg-slate-50 border-slate-200";
}

export default function OrdersSync() {
  const [rows, setRows] = React.useState<Row[]>([]);
  const [loading, setLoading] = React.useState(true);
  const [busy, setBusy] = React.useState(false);
  const [lastRun, setLastRun] = React.useState<number | undefined>(undefined);
  const [filter, setFilter] = React.useState("");

  const load = React.useCallback(async () => {
    setLoading(true);
    try {
      const r = await fetch("/api/orders/sync", { cache: "no-store" });
      const j = await r.json();
      const list: Row[] = Array.isArray(j?.orders)
        ? j.orders.map((o: any) => ({ ...o, selected: false }))
        : [];
      setRows(list);
      setLastRun(j?.lastRun);
    } finally {
      setLoading(false);
    }
  }, []);

  React.useEffect(() => {
    load();
  }, [load]);

  const toggle = (id: string) =>
    setRows((cur) => cur.map((r) => (r.id === id ? { ...r, selected: !r.selected } : r)));

  const toggleAll = (checked: boolean) =>
    setRows((cur) => cur.map((r) => ({ ...r, selected: checked })));

  const trigger = async (mode: "all" | "selected") => {
    setBusy(true);
    try {
      // demo: vi bare simulerer en liten delay
      await new Promise((res) => setTimeout(res, 400));
      // normalt: POST til egen API for å starte sync/eksport
      // await fetch("/api/orders/sync", { method: "POST", body: JSON.stringify({ mode }) })
      await load();
    } finally {
      setBusy(false);
    }
  };

  const filtered = rows.filter((r) => {
    if (!filter) return true;
    const f = filter.toLowerCase();
    return r.id.toLowerCase().includes(f) || r.status.toLowerCase().includes(f) || (r.msg || "").toLowerCase().includes(f);
  });

  const anySelected = rows.some((r) => r.selected);

  return (
    <main className="space-y-6 p-6">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-medium">Orders → Sync</h2>
        <Link href="/admin">← Til Control Center</Link>
      </div>

      <section className="card space-y-3">
        <div className="flex flex-wrap items-center gap-3">
          <button className="btn" onClick={() => load()} disabled={loading || busy}>
            {loading ? "Laster…" : "Last på nytt"}
          </button>
          <button className="btn" onClick={() => trigger("all")} disabled={busy || loading}>
            {busy ? "Kjører…" : "Sync alle"}
          </button>
          <button className="btn" onClick={() => trigger("selected")} disabled={!anySelected || busy || loading}>
            {busy ? "Kjører…" : "Sync valgte"}
          </button>
          <div className="grow" />
          <input
            className="border rounded-lg px-3 py-1.5 text-sm"
            placeholder="Filter (id / status / melding)"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          />
        </div>
        <div className="text-xs opacity-60">
          Sist kjørt: {lastRun ? new Date(lastRun).toLocaleString() : "—"}
        </div>
      </section>

      <section className="card">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-xs opacity-60">
              <tr>
                <th className="py-1.5 pr-3">
                  <input
                    type="checkbox"
                    checked={rows.length > 0 && rows.every((r) => r.selected)}
                    onChange={(e) => toggleAll(e.target.checked)}
                  />
                </th>
                <th className="py-1.5 pr-3">Order ID</th>
                <th className="py-1.5 pr-3">Status</th>
                <th className="py-1.5 pr-3">Oppdatert</th>
                <th className="py-1.5 pr-3">Melding</th>
                <th className="py-1.5 pr-3"></th>
              </tr>
            </thead>
            <tbody>
              {loading && (
                <tr>
                  <td className="py-2 sub" colSpan={6}>
                    Laster…
                  </td>
                </tr>
              )}
              {!loading && filtered.length === 0 && (
                <tr>
                  <td className="py-2 sub" colSpan={6}>
                    Ingen rader
                  </td>
                </tr>
              )}
              {!loading &&
                filtered.map((r) => (
                  <tr key={r.id} className="border-t">
                    <td className="py-1.5 pr-3">
                      <input type="checkbox" checked={!!r.selected} onChange={() => toggle(r.id)} />
                    </td>
                    <td className="py-1.5 pr-3">{r.id}</td>
                    <td className="py-1.5 pr-3">
                      <span className={"px-2 py-0.5 rounded border text-xs " + statusChip(r.status)}>{r.status}</span>
                    </td>
                    <td className="py-1.5 pr-3">{new Date(r.updatedAt).toLocaleString()}</td>
                    <td className="py-1.5 pr-3">{r.msg || "—"}</td>
                    <td className="py-1.5 pr-3">
                      <button
                        className="btn"
                        onClick={() => {
                          toggle(r.id);
                          trigger("selected");
                        }}
                      >
                        Sync linje
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
