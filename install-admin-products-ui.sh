#!/usr/bin/env bash
set -euo pipefail

# ---------- Locate folders ----------
ROOT="${ROOT:-$HOME/Documents/M2}"
# Find a Next.js admin dir (package.json with next in deps)
ADMIN_DIR="${ADMIN_DIR:-$(
  find "$ROOT" -maxdepth 2 -type f -name package.json 2>/dev/null \
  | while read -r f; do
      if jq -e '.dependencies.next // .devDependencies.next' "$f" >/dev/null 2>&1; then
        dirname "$f"; break
      fi
    done
)}"
GATEWAY_DIR="${GATEWAY_DIR:-$ROOT/m2-gateway}"
[ -n "${ADMIN_DIR:-}" ] && [ -d "$ADMIN_DIR" ] || { echo "❌ Fant ikke admin-dir. Sett ADMIN_DIR=<path> og kjør igjen."; exit 1; }

# Ports (can override)
ADMIN_PORT="${ADMIN_PORT:-3000}"
GATEWAY_PORT="${GATEWAY_PORT:-3044}"

echo "➡️  Admin:   $ADMIN_DIR (port $ADMIN_PORT)"
echo "➡️  Gateway: $GATEWAY_DIR (port $GATEWAY_PORT)"

# ---------- Ensure env ----------
mkdir -p "$ADMIN_DIR"
touch "$ADMIN_DIR/.env.local"
if ! grep -q '^NEXT_PUBLIC_GATEWAY_BASE=' "$ADMIN_DIR/.env.local" 2>/dev/null; then
  printf "NEXT_PUBLIC_GATEWAY_BASE=http://localhost:%s\n" "$GATEWAY_PORT" >> "$ADMIN_DIR/.env.local"
fi
if ! grep -q '^NEXT_PUBLIC_GATEWAY=' "$ADMIN_DIR/.env.local" 2>/dev/null; then
  printf "NEXT_PUBLIC_GATEWAY=http://localhost:%s\n" "$GATEWAY_PORT" >> "$ADMIN_DIR/.env.local"
fi
echo "✅ Admin .env.local satt til:"
grep -E '^(NEXT_PUBLIC_GATEWAY(_BASE)?)=' "$ADMIN_DIR/.env.local" | sed 's/^/  /'

# ---------- lib/api.ts (only create if missing) ----------
mkdir -p "$ADMIN_DIR/lib"
API_FILE="$ADMIN_DIR/lib/api.ts"
if [ ! -f "$API_FILE" ]; then
  cat > "$API_FILE" <<'TS'
export const GATEWAY =
  process.env.NEXT_PUBLIC_GATEWAY_BASE ||
  process.env.NEXT_PUBLIC_GATEWAY ||
  "http://localhost:3044";

async function handle(res: Response) {
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(text || `Request failed (${res.status})`);
  }
  return res.json();
}

export async function getJson(path: string) {
  const url = `${GATEWAY}${path}`;
  return handle(await fetch(url, { cache: "no-store" }));
}

export async function postJson(path: string, body: unknown) {
  const url = `${GATEWAY}${path}`;
  return handle(await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }));
}
TS
  echo "✅ Skrev $API_FILE"
else
  echo "ℹ️  $API_FILE finnes – beholder."
fi

# ---------- app/m2/products/page.tsx ----------
PAGE_DIR="$ADMIN_DIR/app/m2/products"
mkdir -p "$PAGE_DIR"
cat > "$PAGE_DIR/page.tsx" <<'TSX'
"use client";

import { useEffect, useMemo, useState } from "react";
import { getJson, postJson } from "@/lib/api";

type Product = {
  sku: string;
  name: string;
  price: number;
  status: number;
  visibility: number;
  extension_attributes?: {
    category_links?: { category_id: string }[];
  };
};

type ListRes = {
  ok: boolean;
  count: number;
  page: number;
  size: number;
  items: Product[];
};

function Badge({ children }: { children: React.ReactNode }) {
  return (
    <span className="px-2 py-0.5 rounded-full text-xs border border-gray-300">
      {children}
    </span>
  );
}

export default function ProductsPage() {
  const [q, setQ] = useState("TEST");
  const [page, setPage] = useState(1);
  const [size, setSize] = useState(20);
  const [data, setData] = useState<ListRes | null>(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [actionMsg, setActionMsg] = useState<string | null>(null);

  const fetchList = async () => {
    setLoading(true);
    setErr(null);
    try {
      const params = new URLSearchParams({ q, page: String(page), size: String(size) });
      const res = await getJson(`/ops/products/list?${params.toString()}`);
      setData(res);
    } catch (e: any) {
      setErr(e?.message || "Feil ved lasting");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchList();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, size]);

  const totals = useMemo(() => {
    if (!data) return null;
    return { count: data.count, page: data.page, size: data.size };
  }, [data]);

  const onSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    setPage(1);
    await fetchList();
  };

  const refreshStats = async () => {
    try {
      const res = await postJson("/ops/stats/refresh", {});
      setActionMsg(`Stats oppdatert: ${new Date().toISOString()}`);
      console.log("stats:", res);
    } catch (e: any) {
      setActionMsg(`Stats refresh feilet: ${e?.message || "Ukjent feil"}`);
    }
    setTimeout(() => setActionMsg(null), 3500);
  };

  const replaceCats = async (sku: string) => {
    const input = window.prompt(`Skriv kategori-IDer for ${sku} (kommadelt, f.eks 2,5,7):`, "");
    if (input == null) return;
    const ids = input.split(",").map(s => s.trim()).filter(Boolean).map(Number).filter(n => Number.isFinite(n));
    if (!ids.length) { alert("Ingen gyldige IDer."); return; }
    try {
      const res = await postJson("/ops/category/replace", { items: [{ sku, categoryIds: ids }] });
      setActionMsg(`Kategorier oppdatert for ${sku}`);
      console.log("replaceCats:", res);
      fetchList();
    } catch (e: any) {
      alert(e?.message || "Feil ved oppdatering");
    }
  };

  const healVariant = async (sku: string) => {
    // rask dialog – du kan gjøre dette fancy senere
    const parentSku = window.prompt("Parent (configurable) SKU:", "TEST-CFG");
    if (!parentSku) return;
    const cfgAttr = window.prompt("Konfig attributt:", "cfg_color") || "cfg_color";
    const cfgValueStr = window.prompt("Konfig verdi (ID):", "7") || "7";
    const label = window.prompt("Label:", "Blue") || "Blue";
    const websiteIdStr = window.prompt("Website ID:", "1") || "1";
    const qtyStr = window.prompt("Stock qty:", "5") || "5";

    const cfgValue = Number(cfgValueStr);
    const websiteId = Number(websiteIdStr);
    const qty = Number(qtyStr);

    try {
      const res = await postJson("/ops/variant/heal", {
        parentSku, sku, cfgAttr, cfgValue, label, websiteId,
        stock: { source_code: "default", quantity: qty, status: 1 },
      });
      setActionMsg(`Variant heal OK for ${sku}`);
      console.log("heal:", res);
    } catch (e: any) {
      alert(e?.message || "Feil ved heal");
    }
  };

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-semibold">🔎 Produkter</h1>

      <form onSubmit={onSearch} className="flex items-center gap-2">
        <input
          className="border rounded px-3 py-2 w-64"
          placeholder="Søk (SKU/ navn)…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <select className="border rounded px-2 py-2" value={size} onChange={e => setSize(Number(e.target.value))}>
          {[10,20,50,100].map(n => <option key={n} value={n}>{n} / side</option>)}
        </select>
        <button className="px-3 py-2 rounded bg-black text-white" type="submit">Søk</button>
        <button type="button" onClick={refreshStats} className="px-3 py-2 rounded border">↻ Oppdater stats</button>
        {actionMsg && <span className="text-sm opacity-70 ml-2">{actionMsg}</span>}
      </form>

      {loading && <div>Laster…</div>}
      {err && <div className="text-red-600">Feil: {err}</div>}

      {totals && (
        <div className="text-sm opacity-70">
          Treff: <b>{totals.count}</b> • Side {totals.page} • {totals.size} per side
        </div>
      )}

      <div className="overflow-auto border rounded">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="bg-gray-50 text-left">
              <th className="p-2">SKU</th>
              <th className="p-2">Navn</th>
              <th className="p-2">Pris</th>
              <th className="p-2">Status</th>
              <th className="p-2">Vis</th>
              <th className="p-2">Kategorier</th>
              <th className="p-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {(data?.items || []).map((p) => {
              const cats = (p.extension_attributes?.category_links || []).map(c => c.category_id).join(",");
              const status = p.status === 1 ? "Enabled" : "Disabled";
              const visMap: Record<number, string> = {1:"Not Visible",2:"Catalog",3:"Search",4:"Catalog+Search"};
              const vis = visMap[p.visibility] || String(p.visibility);
              return (
                <tr key={p.sku} className="border-t">
                  <td className="p-2 font-mono">{p.sku}</td>
                  <td className="p-2">{p.name}</td>
                  <td className="p-2">{p.price}</td>
                  <td className="p-2"><Badge>{status}</Badge></td>
                  <td className="p-2"><Badge>{vis}</Badge></td>
                  <td className="p-2">{cats}</td>
                  <td className="p-2 space-x-2">
                    <button className="px-2 py-1 rounded border" onClick={() => replaceCats(p.sku)}>Set cats…</button>
                    <button className="px-2 py-1 rounded border" onClick={() => healVariant(p.sku)}>Heal…</button>
                  </td>
                </tr>
              );
            })}
            {(!data || data.items.length === 0) && (
              <tr><td className="p-4 text-center opacity-70" colSpan={7}>Ingen produkter</td></tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center gap-2">
        <button
          className="px-3 py-2 rounded border disabled:opacity-40"
          disabled={page <= 1}
          onClick={() => setPage((p) => Math.max(1, p - 1))}
        >
          ← Forrige
        </button>
        <span className="text-sm opacity-70">Side {page}</span>
        <button
          className="px-3 py-2 rounded border"
          onClick={() => setPage((p) => p + 1)}
        >
          Neste →
        </button>
      </div>
    </div>
  );
}
TSX
echo "✅ Skrev admin-side: $PAGE_DIR/page.tsx"

# ---------- Friendly pointer ----------
echo "➡️  Åpne:  http://localhost:$ADMIN_PORT/m2/products"
echo "   (Admin peker mot gateway: $(grep -Eo 'NEXT_PUBLIC_GATEWAY_BASE=.*' "$ADMIN_DIR/.env.local" | cut -d= -f2))"
