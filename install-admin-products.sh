#!/usr/bin/env bash
set -euo pipefail

# ── Finn admin (Next.js) og gateway ─────────────────────────────────────────────
ADMIN_DIR="${ADMIN_DIR:-}"
GATEWAY_DIR="${GATEWAY_DIR:-}"

if [ -z "${ADMIN_DIR}" ]; then
  ADMIN_DIR="$(
    find "$HOME/Documents/M2" -type f -name package.json 2>/dev/null \
    | while read -r f; do
        jq -e '.dependencies.next // .devDependencies.next' "$f" >/dev/null 2>&1 \
        && dirname "$f" && break
      done
  )"
fi

if [ -z "${GATEWAY_DIR}" ]; then
  # typisk m2-gateway under Documents/M2
  if [ -d "$HOME/Documents/M2/m2-gateway" ]; then
    GATEWAY_DIR="$HOME/Documents/M2/m2-gateway"
  else
    GATEWAY_DIR="$(dirname "$(pwd)")/m2-gateway"
  fi
fi

[ -d "$ADMIN_DIR" ]   || { echo "❌ Fant ikke admin-dir"; exit 1; }
[ -d "$GATEWAY_DIR" ] || { echo "❌ Fant ikke gateway-dir"; exit 1; }

ADMIN_PORT="${ADMIN_PORT:-3000}"
GATEWAY_PORT="${GATEWAY_PORT:-3044}"

echo "➡️  Admin:   $ADMIN_DIR (port ${ADMIN_PORT})"
echo "➡️  Gateway: $GATEWAY_DIR (port ${GATEWAY_PORT})"

# ── Sørg for at admin peker på gateway ─────────────────────────────────────────
mkdir -p "$ADMIN_DIR"
touch "$ADMIN_DIR/.env.local"
grep -q '^NEXT_PUBLIC_GATEWAY_BASE=' "$ADMIN_DIR/.env.local" 2>/dev/null \
  && sed -i '' -E "s|^NEXT_PUBLIC_GATEWAY_BASE=.*|NEXT_PUBLIC_GATEWAY_BASE=http://localhost:${GATEWAY_PORT}|" "$ADMIN_DIR/.env.local" \
  || printf "NEXT_PUBLIC_GATEWAY_BASE=http://localhost:%s\n" "${GATEWAY_PORT}" >> "$ADMIN_DIR/.env.local"

grep -q '^NEXT_PUBLIC_GATEWAY=' "$ADMIN_DIR/.env.local" 2>/dev/null \
  && sed -i '' -E "s|^NEXT_PUBLIC_GATEWAY=.*|NEXT_PUBLIC_GATEWAY=http://localhost:${GATEWAY_PORT}|" "$ADMIN_DIR/.env.local" \
  || printf "NEXT_PUBLIC_GATEWAY=http://localhost:%s\n" "${GATEWAY_PORT}" >> "$ADMIN_DIR/.env.local"

echo "✅ Admin .env.local oppdatert:"
grep -E 'NEXT_PUBLIC_GATEWAY(_BASE)?=' "$ADMIN_DIR/.env.local"

# ── Opprett lib/api.ts (om mangler) ────────────────────────────────────────────
mkdir -p "$ADMIN_DIR/lib"
if [ ! -f "$ADMIN_DIR/lib/api.ts" ]; then
  cat > "$ADMIN_DIR/lib/api.ts" <<'TS'
export const GATEWAY =
  process.env.NEXT_PUBLIC_GATEWAY_BASE ||
  process.env.NEXT_PUBLIC_GATEWAY ||
  "http://localhost:3044";

export async function getJson<T = any>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${GATEWAY}${path}`, {
    method: "GET",
    ...init,
    headers: { "Content-Type": "application/json", ...(init?.headers || {}) },
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET ${path} -> ${res.status}`);
  return res.json();
}

export async function postJson<T = any>(path: string, body?: any, init?: RequestInit): Promise<T> {
  const res = await fetch(`${GATEWAY}${path}`, {
    method: "POST",
    body: body ? JSON.stringify(body) : undefined,
    ...init,
    headers: { "Content-Type": "application/json", ...(init?.headers || {}) },
  });
  if (!res.ok) throw new Error(`POST ${path} -> ${res.status}`);
  return res.json();
}
TS
  echo "✅ Skrev $ADMIN_DIR/lib/api.ts"
else
  echo "ℹ️  $ADMIN_DIR/lib/api.ts finnes – beholder."
fi

# ── Lag admin-side: /m2/products ───────────────────────────────────────────────
mkdir -p "$ADMIN_DIR/app/m2/products"
cat > "$ADMIN_DIR/app/m2/products/page.tsx" <<'TSX'
"use client";
import { useEffect, useMemo, useState } from "react";
import { getJson } from "@/lib/api";

type M2Product = {
  sku: string;
  name?: string;
  price?: number;
  status?: number;
  visibility?: number;
  extension_attributes?: {
    category_links?: { category_id: string | number }[];
  };
};

type ListResp = { ok: boolean; count: number; page: number; size: number; items: M2Product[] };

export default function ProductsPage() {
  const [data, setData] = useState<ListResp | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [size, setSize] = useState(25);
  const [q, setQ] = useState("");

  const load = async (_page = page, _size = size) => {
    setErr(null);
    try {
      const qs = new URLSearchParams({ page: String(_page), size: String(_size) });
      if (q.trim()) qs.set("q", q.trim());
      // Primær: gateway /ops/products/list
      const res = await getJson<ListResp>(`/ops/products/list?${qs.toString()}`);
      setData(res);
    } catch (e: any) {
      setErr(e?.message || "Ukjent feil");
    }
  };

  useEffect(() => { load(1, size); /* eslint-disable-next-line */ }, [size]);

  const rows = useMemo(() => data?.items ?? [], [data]);

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-semibold">Produkter</h1>

      <div className="flex gap-2 items-center">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Søk (SKU eller navn)…"
          className="border rounded px-3 py-2 w-72"
        />
        <button onClick={() => load(1, size)} className="rounded px-3 py-2 border">Søk</button>
        <button onClick={() => { setQ(""); load(1, size); }} className="rounded px-3 py-2 border">Tøm</button>
        <div className="ml-auto flex items-center gap-2">
          <label>Per side</label>
          <select
            value={size}
            onChange={(e) => setSize(Number(e.target.value))}
            className="border rounded px-2 py-1"
          >
            {[10,25,50,100].map(n => <option key={n} value={n}>{n}</option>)}
          </select>
          <button onClick={() => load(page, size)} className="rounded px-3 py-2 border">↻ Refresh</button>
        </div>
      </div>

      {err && <div className="text-red-600">Feil: {String(err)}</div>}

      {!data && !err && <div>Laster…</div>}

      {data && (
        <>
          <div className="text-sm text-gray-600">
            Viser {rows.length} av side {data.page} (størrelse {data.size})
          </div>
          <div className="overflow-auto border rounded">
            <table className="min-w-[800px] w-full">
              <thead className="bg-gray-50 text-left">
                <tr>
                  <th className="px-3 py-2">SKU</th>
                  <th className="px-3 py-2">Navn</th>
                  <th className="px-3 py-2">Pris</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Synlighet</th>
                  <th className="px-3 py-2">Kategorier</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((p) => {
                  const cats = p.extension_attributes?.category_links?.map(c => String(c.category_id)) ?? [];
                  return (
                    <tr key={p.sku} className="border-t">
                      <td className="px-3 py-2 font-mono">{p.sku}</td>
                      <td className="px-3 py-2">{p.name ?? <em className="text-gray-500">–</em>}</td>
                      <td className="px-3 py-2">{p.price ?? <em className="text-gray-500">–</em>}</td>
                      <td className="px-3 py-2">{p.status}</td>
                      <td className="px-3 py-2">{p.visibility}</td>
                      <td className="px-3 py-2">{cats.join(", ")}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          <div className="flex gap-2 items-center">
            <button
              disabled={page<=1}
              onClick={() => { const np = Math.max(1, page-1); setPage(np); load(np, size); }}
              className="rounded px-3 py-2 border disabled:opacity-50"
            >
              ← Forrige
            </button>
            <div>Side {page}</div>
            <button
              onClick={() => { const np = page+1; setPage(np); load(np, size); }}
              className="rounded px-3 py-2 border"
            >
              Neste →
            </button>
          </div>
        </>
      )}
    </div>
  );
}
TSX
echo "✅ Skrev admin-side: $ADMIN_DIR/app/m2/products/page.tsx"

# ── Patch gateway: legg til /ops/products/list om den mangler ──────────────────
cd "$GATEWAY_DIR"
if ! grep -q "app.get('/ops/products/list'" server.js 2>/dev/null; then
  cp server.js server.js.bak.$(date +%s)
  # legg route helt på slutten før app.listen
  perl -0777 -pe 's|(app\.listen\([^\n]+\);)|
// --- auto: products list route ---
const axiosProducts = require("axios");
app.get("/ops/products/list", async (req, res) => {
  try {
    const base = process.env.MAGENTO_BASE;
    const tok  = process.env.MAGENTO_TOKEN;
    const page = Number(req.query.page||1);
    const size = Number(req.query.size||50);
    const q    = (req.query.q||"").toString().trim();

    // Fields: ta med det vi viser i tabellen
    const fields = "items[sku,name,price,status,visibility,extension_attributes[category_links[category_id]]]";

    const params = new URLSearchParams();
    params.set("searchCriteria[currentPage]", String(page));
    params.set("searchCriteria[pageSize]", String(size));
    if (q) {
      // søk i sku OR navn
      params.set("searchCriteria[filter_groups][0][filters][0][field]", "sku");
      params.set("searchCriteria[filter_groups][0][filters][0][value]", "%" + q + "%");
      params.set("searchCriteria[filter_groups][0][filters][0][condition_type]", "like");
      params.set("searchCriteria[filter_groups][1][filters][0][field]", "name");
      params.set("searchCriteria[filter_groups][1][filters][0][value]", "%" + q + "%");
      params.set("searchCriteria[filter_groups][1][filters][0][condition_type]", "like");
    }
    params.set("fields", fields);

    const url = base.replace(/\/+$/,"") + "/rest/all/V1/products?" + params.toString();
    const r = await axiosProducts.get(url, {
      headers: { "Authorization": tok, "Content-Type": "application/json" },
      timeout: Number(process.env.MAGENTO_TIMEOUT_MS||25000)
    });
    const items = Array.isArray(r.data?.items) ? r.data.items : [];
    res.json({ ok: true, count: items.length, page, size, items });
  } catch (err) {
    const code = err?.response?.status || 500;
    const msg  = err?.response?.data || { message: String(err) };
    res.status(code).json({ ok: false, error: msg });
  }
});
// --- end auto route ---
$1|s' -i server.js
  echo "✅ Gateway patched: /ops/products/list"
else
  echo "ℹ️  Gateway hadde allerede /ops/products/list"
fi

# ── Start/restart prosesser (om ønskelig) ──────────────────────────────────────
echo "�� Starter gateway (port ${GATEWAY_PORT})…"
pkill -f "node server.js" 2>/dev/null || true
( cd "$GATEWAY_DIR" && PORT="${GATEWAY_PORT}" node server.js ) >/dev/null 2>&1 &

echo "🚀 Starter admin (Next.js port ${ADMIN_PORT})…"
( cd "$ADMIN_DIR" && npm run dev -- -p "${ADMIN_PORT}" ) >/dev/null 2>&1 &

sleep 1
echo "🧪 Sanity:"
curl -sS "http://localhost:${GATEWAY_PORT}/health/magento" | jq .
curl -sS "http://localhost:${GATEWAY_PORT}/ops/stats/summary" | jq .

echo "➡️  Admin produkter: http://localhost:${ADMIN_PORT}/m2/products"
echo "➡️  Gateway list:   http://localhost:${GATEWAY_PORT}/ops/products/list"
echo "✅ Ferdig."
