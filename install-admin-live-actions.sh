#!/usr/bin/env bash
set -euo pipefail

# --- 0) Finn kataloger --------------------------------------------------------
ROOT="${1:-$HOME/Documents/M2}"

find_dir () {
  local needle="$1"
  find "$ROOT" -maxdepth 3 -type d -name "$needle" 2>/dev/null | head -n1
}

ADMIN_DIR="${ADMIN_DIR:-$(find "$ROOT" -type f -name package.json -maxdepth 3 2>/dev/null \
  | while read -r f; do
      if jq -e '.dependencies.next // .devDependencies.next' "$f" >/dev/null 2>&1; then
        dirname "$f"; break
      fi
    done)}"

GATEWAY_DIR="${GATEWAY_DIR:-$(find_dir m2-gateway)}"

[ -d "$ADMIN_DIR" ]   || { echo "❌ Fant ikke admin-prosjekt"; exit 1; }
[ -d "$GATEWAY_DIR" ] || { echo "❌ Fant ikke gateway-prosjekt"; exit 1; }

ADMIN_PORT="${ADMIN_PORT:-3000}"
GATEWAY_PORT="${GATEWAY_PORT:-3044}"
GATEWAY_BASE="http://localhost:${GATEWAY_PORT}"

echo "➡️  Admin:   $ADMIN_DIR (port $ADMIN_PORT)"
echo "➡️  Gateway: $GATEWAY_DIR (port $GATEWAY_PORT)"

# --- 1) Sikre admin/.env.local ----------------------------------------------
ADMIN_ENV="$ADMIN_DIR/.env.local"
touch "$ADMIN_ENV"
perl -0777 -pe '
  sub setkv { my($t,$k,$v)=@_; $t =~ s/^\Q$k\E=.*/$k='"'"'$v'"'"'/m or $t .= "\n$k=$v\n"; return $t }
  $_ = do { local $/; <> };
  $_ = setkv($_,"NEXT_PUBLIC_GATEWAY_BASE","'"$GATEWAY_BASE"'");
  $_ = setkv($_,"NEXT_PUBLIC_GATEWAY","'"$GATEWAY_BASE"'");   # legacy
  print $_;
' -i "$ADMIN_ENV"
echo "✅ Oppdatert $ADMIN_ENV"

# --- 2) lib/api.ts med getJson/postJson --------------------------------------
LIB_DIR="$ADMIN_DIR/lib"
mkdir -p "$LIB_DIR"
LIB_API="$LIB_DIR/api.ts"

if [ -f "$LIB_API" ]; then cp "$LIB_API" "$LIB_API.bak"; fi

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
echo "✅ Skrev $LIB_API (backup: $LIB_API.bak)"

# --- 3) app/m2/page.tsx med Live Actions -------------------------------------
APP_DIR="$ADMIN_DIR/app/m2"
mkdir -p "$APP_DIR"
PAGE="$APP_DIR/page.tsx"
if [ -f "$PAGE" ]; then cp "$PAGE" "$PAGE.bak"; fi

cat > "$PAGE" <<'TSX'
"use client";
import { useEffect, useState } from "react";
import { getJson, postJson } from "@/lib/api";

type Stats = { ok: boolean; ts?: string; totals?: { products: number; categories: number; variants: number } };
type Health = { ok: boolean } | { ok: false; error?: any };

export default function M2Dashboard() {
  const [health, setHealth] = useState<Health | null>(null);
  const [stats, setStats] = useState<Stats | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string>("");

  // Forms state
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
    try {
      const h = await getJson("/health/magento");
      setHealth(h);
    } catch (e: any) {
      setHealth({ ok: false, error: e?.message || String(e) });
    }
    try {
      const s = await getJson("/ops/stats/summary");
      setStats(s);
    } catch (e) {
      setStats({ ok: false });
    }
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
        const categoryIds = (ids || "").split(",").map(s => s.trim()).filter(Boolean).map(n => Number(n));
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
          <button
            onClick={doStatsRefresh}
            disabled={busy}
            className="px-3 py-2 rounded bg-black text-white text-sm disabled:opacity-50"
          >
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
echo "✅ Skrev $PAGE (backup: $PAGE.bak)"

# --- 4) Next dev-port i admin/package.json -----------------------------------
ADMIN_PKG="$ADMIN_DIR/package.json"
if [ -f "$ADMIN_PKG" ]; then
  cp "$ADMIN_PKG" "$ADMIN_PKG.bak"
  node - "$ADMIN_PKG" "$ADMIN_PORT" <<'NODE'
const fs = require('fs');
const [,, pkgPath, port] = process.argv;
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
pkg.scripts = pkg.scripts || {};
pkg.scripts.dev = `next dev -p ${port}`;
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2));
NODE
  echo "✅ Oppdatert dev-script i $ADMIN_PKG (backup: $ADMIN_PKG.bak)"
fi

# --- 5) Start admin (hvis ikke kjører allerede) ------------------------------
echo "🚀 Starter admin (Next.js port $ADMIN_PORT)…"
( cd "$ADMIN_DIR" && nohup npm run dev >/dev/null 2>&1 & )

echo "➡️  Åpne: http://localhost:$ADMIN_PORT/m2"
