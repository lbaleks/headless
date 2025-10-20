"use client";
import { useState } from "react";

export default function DraftsSync() {
  const [log, setLog] = useState<string>("");
  const [busy, setBusy] = useState(false);

  async function run() {
    setBusy(true);
    setLog("Synker…");
    try {
      const r = await fetch("/api/draft/sync", { method: "POST" });
      const j = await r.json();
      setLog(JSON.stringify(j, null, 2));
    } catch (e: any) {
      setLog("❌ " + (e?.message || "unknown_error"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="p-6 space-y-3">
      <h1 className="text-2xl font-bold">🧩 AI-utkast → Magento</h1>
      <p className="text-sm opacity-70">Sender alle usynkede utkast til gatewayen.</p>
      <button
        disabled={busy}
        onClick={run}
        className="px-3 py-2 rounded border hover:bg-black/5 disabled:opacity-50"
      >
        {busy ? "Synker…" : "Send alle usynkede nå"}
      </button>
      <pre className="text-xs bg-black/5 p-3 rounded max-h-72 overflow-auto">{log}</pre>
    </div>
  );
}
