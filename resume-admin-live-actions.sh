#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$HOME/Documents/M2}"

# Finn admin-prosjekt (Next.js)
ADMIN_DIR="${ADMIN_DIR:-$(find "$ROOT" -type f -name package.json -maxdepth 3 2>/dev/null \
  | while read -r f; do
      jq -e '.dependencies.next // .devDependencies.next' "$f" >/dev/null 2>&1 && dirname "$f" && break
    done)}"
[ -d "$ADMIN_DIR" ] || { echo "❌ Fant ikke admin-prosjekt"; exit 1; }

ADMIN_PORT="${ADMIN_PORT:-3000}"
echo "➡️  Admin: $ADMIN_DIR (port $ADMIN_PORT)"

# 2) lib/api.ts
LIB_DIR="$ADMIN_DIR/lib"
mkdir -p "$LIB_DIR"
LIB_API="$LIB_DIR/api.ts"
[ -f "$LIB_API" ] && cp "$LIB_API" "$LIB_API.bak"

cat > "$LIB_API" <<'TS'
export const GATEWAY =
  process.env.NEXT_PUBLIC_GATEWAY_BASE ||
  process.env.NEXT_PUBLIC_GATEWAY ||
  "http://localhost:3044";

async function handle(res: Response) {
  const ct = res.headers.get("content-type") || "";
  const data = ct.includes("application/json") ? await res.json().catch(() => ({})) : await res.text();
  if (!res.ok) {
    const msg = (data && (data.message || data.error)) || res.statusText;
    throw new Error(typeof msg === "string" ? msg : JSON.stringify(data));
  }
  return data;
}

export async function getJson(path: string) {
  const res = await fetch(`${GATEWAY}${path}`, { method: "GET", cache: "no-store" });
  return handle(res);
}

export async function postJson(path: string, body: any) {
  const res = await fetch(`${GATEWAY}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return handle(res);
}
TS
echo "✅ Skrev $LIB_API ${LIB_API:+(backup: $LIB_API.bak)}"

# 3) app/m2/page.tsx
APP_DIR="$ADMIN_DIR/app/m2"
mkdir -p "$APP_DIR"
PAGE="$APP_DIR/page.tsx"
[ -f "$PAGE" ] && cp "$PAGE" "$PAGE.bak"

cat > "$PAGE" <<'TSX'
"use client";
import { useEffect, useState } from "react";
// bruk RELATIV import så vi slipper alias-oppsett
import { getJson, postJson } from "../../lib/api";

type Stats = { ok: boolean; ts?: string; totals?: { products: number; categories: number; variants: number } };
type Health = { ok: boolean } | { ok: false; error?: any };

export default function M2Dashboard() {
  const [health, setHealth] = useState<Health | null>(null);
  const [stats, setStats] = useState<Stats | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string>("");

  const [heal, setHeal] = useState({
    parentSku: "TEST-CFG",
    sku: "TEST-BLUE-EXTRA",
    cfgAttr: "cfg_color",
    cfgValue: 7,
    label: "Blue",
    websiteId: 1,
    quantity: 5,
    status: 1,
  });

  const [catRows, setCatRows] = useState<string>([
    "TEST-RED:2,4",
    "TEST-GREEN:2,5,7",
    "TEST-BLUE-EXTRA:2,7",
  ].join("\n"));

  const refresh = async () => {
    try { setHealth(await getJson("/health/magento")); }
    catch (e: any) { setHealth({ ok: false, error: e?.message || String(e) }); }

    try { setStats(await getJson("/ops/stats/summary")); }
    catch { setStats({ ok: false } as any); }
  };

  useEffect(() => { refresh(); }, []);

  const doStatsRefresh = async () => {
    setBusy(true); setMsg("");
    try {
      await postJson("/ops/stats/refresh", {});
      await refresh();
      setMsg("Stats oppdatert ✅");
    } catch (e: any) {
      setMsg("Stats refresh feilet: " + (e?.message || String(e)));
    } finally { setBusy(false); }
  };

  const doHeal = async () => {
    setBusy(true); setMsg("");
    try {
      const payload = {
        parentSku: heal.parentSku,
        sku: heal.sku,
        cfgAttr: heal.cfgAttr,
        cfgValue: Number(heal.cfgValue),
        label: heal.label,
        websiteId: Number(heal.websiteId),
        stock: { source_code: "default", quantity: Number(heal.quantity), status: Number(heal.status) },
      };
      const r = await postJson("/ops/variant/heal", payload);
      setMsg("Heal OK ✅ " + JSON.stringify(r));
      await refresh();
    } catch (e: any) {
      setMsg("Heal feilet: " + (e?.message || String(e)));
    } finally { setBusy(false); }
  };

  const doCategoryReplace = async () => {
    setBusy(true); setMsg("");
    try {
      const lines = catRows.split("\n").map(l => l.trim()).filter(Boolean);
      const items = lines.map(line => {
        const [sku, ids] = line.split(":");
        const categoryIds = (ids || "").split(",").map(s => s.trim()).filter(Boolean).map(Number);
        return { sku: sku.trim(), categoryIds };
      });
      const r = await postJson("/ops/category/replace", { items });
      setMsg("Category replace OK ✅ " + JSON.stringify(r));
      await refresh();
    } catch (e: any) {
      setMsg("Category replace feilet: " + (e?.message || String(e)));
    } finally { setBusy(false); }
  };

  const Card: React.FC<{ title: string, children: any }> = ({ title, children }) => (
    <div className="rounded-2xl shadow p-4 border bg-white">
      <div className="font-semibold mb-2">{title}</div>
      <div className="text-sm">{children}</div>
    </div>
  );

  return (
    <div className="mx-auto max-w-5xl p-6 space-y-6">
      <h1 className="text-2xl font-bold">🔗 Gateway / Magento</h1>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card title="Health">
          <pre className="text-xs bg-gray-50 p-2 rounded">{JSON.stringify(health, null, 2)}</pre>
        </Card>
        <Card title="Stats">
          {stats?.ok && stats?.totals ? (
            <div className="space-y-1">
              <div>🧩 Products: <b>{stats.totals.products}</b></div>
              <div>🏷 Categories: <b>{stats.totals.categories}</b></div>
              <div>🌈 Variants: <b>{stats.totals.variants}</b></div>
              <div className="text-xs text-gray-500">ts: {stats.ts}</div>
            </div>
          ) : (
            <div className="text-gray-500">Ingen statistikk tilgjengelig.</div>
          )}
        </Card>
        <Card title="Actions">
          <button onClick={doStatsRefresh} disabled={busy} className="px-3 py-2 rounded bg-black text-white text-sm disabled:opacity-50">
            ↻ Oppdater stats
          </button>
          {msg && <div className="text-xs text-gray-600 mt-2 break-all">{msg}</div>}
        </Card>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card title="Heal Variant">
          <div className="grid grid-cols-2 gap-2">
            {[
              ["parentSku","Parent SKU"],
              ["sku","Child SKU"],
              ["cfgAttr","Config attr"],
              ["cfgValue","Config value"],
              ["label","Label"],
              ["websiteId","Website ID"],
              ["quantity","Stock qty"],
              ["status","Stock status (1=In stock)"],
            ].map(([k,label]) => (
              <label key={k} className="text-xs">
                <div className="mb-1 text-gray-500">{label}</div>
                <input
                  className="w-full border rounded px-2 py-1"
                  value={(heal as any)[k]}
                  onChange={e => setHeal({ ...heal, [k]: e.target.value })}
                />
              </label>
            ))}
          </div>
          <div className="mt-3">
            <button onClick={doHeal} disabled={busy} className="px-3 py-2 rounded bg-black text-white text-sm disabled:opacity-50">
              🩹 Heal now
            </button>
          </div>
        </Card>

        <Card title="Category Replace">
          <p className="text-xs text-gray-500 mb-2">
            Format: <code>SKU:ID,ID,ID</code> – én per linje.
          </p>
          <textarea
            className="w-full h-40 border rounded p-2 font-mono text-xs"
            value={catRows}
            onChange={e => setCatRows(e.target.value)}
          />
          <div className="mt-3">
            <button onClick={doCategoryReplace} disabled={busy} className="px-3 py-2 rounded bg-black text-white text-sm disabled:opacity-50">
              🏷 Replace categories
            </button>
          </div>
        </Card>
      </div>
    </div>
  );
}
TSX
echo "✅ Skrev $PAGE ${PAGE:+(backup: $PAGE.bak)}"

# 4) Oppdater dev-port
PKG="$ADMIN_DIR/package.json"
if [ -f "$PKG" ]; then
  cp "$PKG" "$PKG.bak"
  node - "$PKG" "$ADMIN_PORT" <<'NODE'
const fs = require('fs');
const [,, p, port] = process.argv;
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.scripts = pkg.scripts || {};
pkg.scripts.dev = `next dev -p ${port}`;
fs.writeFileSync(p, JSON.stringify(pkg, null, 2));
NODE
  echo "✅ Oppdatert dev-script i $PKG (backup: $PKG.bak)"
fi

# 5) Start admin
echo "🚀 Starter admin (Next.js port $ADMIN_PORT)…"
( cd "$ADMIN_DIR" && nohup npm run dev >/dev/null 2>&1 & )
echo "➡️  Åpne: http://localhost:$ADMIN_PORT/m2"
