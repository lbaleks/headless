"use client";
import { useState } from "react";

export default function SyncButtons() {
  const [busy, setBusy] = useState(false);
  const [last, setLast] = useState<string | null>(null);

  async function run() {
    try {
      setBusy(true);
      const r = await fetch("/api/jobs/run-sync", { method: "POST" });
      const j = await r.json();
      setLast(j?.id ?? "OK");
    } catch (e) {
      setLast("error");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={run}
        disabled={busy}
        className="px-3 py-1 rounded bg-black text-white disabled:opacity-50"
      >
        {busy ? "Syncing…" : "Sync now"}
      </button>
      {last && <span className="text-xs text-neutral-600">Last: {last}</span>}
    </div>
  );
}
