#!/usr/bin/env bash
set -euo pipefail

ADMIN_DIR="${ADMIN_DIR:-}"
# Finn admin-mappen automatisk om ikke satt
if [ -z "${ADMIN_DIR}" ]; then
  ADMIN_DIR="$(
    find "$HOME/Documents/M2" -type f -name package.json 2>/dev/null \
    | while read -r f; do
        if jq -e '.dependencies.next // .devDependencies.next' "$f" >/dev/null 2>&1; then
          dirname "$f"; break
        fi
      done
  )"
fi

[ -n "${ADMIN_DIR}" ] && [ -d "${ADMIN_DIR}" ] || { echo "❌ Fant ikke admin-dir. Set ADMIN_DIR eller plasser prosjektet under ~/Documents/M2"; exit 1; }

GATEWAY_BASE_DEFAULT="http://localhost:3044"
ENV_LOCAL="${ADMIN_DIR}/.env.local"

echo "➡️  Admin:   ${ADMIN_DIR}"
echo "➡️  Gateway: ${GATEWAY_BASE_DEFAULT}"

mkdir -p "${ADMIN_DIR}/app/m2" "${ADMIN_DIR}/app/m2/products" "${ADMIN_DIR}/app/m2/categories" "${ADMIN_DIR}/lib"

# 1) Sørg for at .env.local peker på gateway
touch "${ENV_LOCAL}"
grep -q '^NEXT_PUBLIC_GATEWAY_BASE=' "${ENV_LOCAL}" 2>/dev/null || echo "NEXT_PUBLIC_GATEWAY_BASE=${GATEWAY_BASE_DEFAULT}" >> "${ENV_LOCAL}"
# Behold evt. gammel nøkkel for bakoverkomp.
grep -q '^NEXT_PUBLIC_GATEWAY=' "${ENV_LOCAL}" 2>/dev/null || echo "NEXT_PUBLIC_GATEWAY=${GATEWAY_BASE_DEFAULT}" >> "${ENV_LOCAL}"
echo "✅ Admin .env.local er konfigurert."

# 2) Solid fetch-wrapper (erstatter forutsigbart)
cat > "${ADMIN_DIR}/lib/api.ts" <<'TS'
"use client";

export const GATEWAY =
  process.env.NEXT_PUBLIC_GATEWAY_BASE ||
  process.env.NEXT_PUBLIC_GATEWAY ||
  "http://localhost:3044";

async function handle(res: Response) {
  const text = await res.text();
  let data: any = undefined;
  try { data = text ? JSON.parse(text) : undefined; } catch (_) { /* noop */ }
  if (!res.ok) {
    const msg = data?.error || data?.message || res.statusText || "Request failed";
    throw new Error(typeof msg === "string" ? msg : JSON.stringify(msg));
  }
  return data;
}

export const api = {
  async get(path: string) {
    const url = `${GATEWAY}${path}`;
    const res = await fetch(url, { cache: "no-store" });
    return handle(res);
  },
  async post(path: string, body: any) {
    const url = `${GATEWAY}${path}`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return handle(res);
  },
};
TS
echo "✅ Skrev lib/api.ts"

# 3) /m2 – enkel hub
cat > "${ADMIN_DIR}/app/m2/page.tsx" <<'TSX'
"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";

export default function M2Home() {
  const [health, setHealth] = useState<any>(null);
  const [stats, setStats] = useState<any>(null);
  const [err, setErr] = useState<string>("");

  useEffect(() => {
    api.get("/health/magento").then(setHealth).catch(e=>setErr(String(e.message||e)));
    api.get("/ops/stats/summary").then(setStats).catch(()=>{/* ok if missing */});
  }, []);

  return (
    <div className="p-6 space-y-6">
      <h1 className="text-2xl font-bold">🔗 Gateway / Magento</h1>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="p-4 rounded-xl border">
          <h2 className="font-semibold mb-2">Health</h2>
          <pre className="text-sm bg-black/5 p-3 rounded">{JSON.stringify(health, null, 2)}</pre>
          {err && <p className="text-red-600 text-sm mt-2">Error: {err}</p>}
        </div>

        <div className="p-4 rounded-xl border">
          <h2 className="font-semibold mb-2">Stats</h2>
          {stats?.ok ? (
            <div className="space-y-1 text-sm">
              <div>🧩 Products: {stats?.totals?.products ?? "?"}</div>
              <div>🏷 Categories: {stats?.totals?.categories ?? "?"}</div>
              <div>🌈 Variants: {stats?.totals?.variants ?? "?"}</div>
              <div className="text-xs text-gray-500">ts: {stats?.ts}</div>
            </div>
          ) : (
            <div className="text-sm text-gray-500">Ingen statistikk tilgjengelig.</div>
          )}
        </div>
      </div>

      <div className="flex items-center gap-3">
        <Link className="px-3 py-2 rounded-lg border hover:bg-black/5" href="/m2/products">📦 Produkter</Link>
        <Link className="px-3 py-2 rounded-lg border hover:bg-black/5" href="/m2/categories">🗂 Kategorier</Link>
      </div>
    </div>
  );
}
TSX
echo "✅ Skrev /app/m2/page.tsx"

# 4) /m2/products – live-søk + tabell
cat > "${ADMIN_DIR}/app/m2/products/page.tsx" <<'TSX'
"use client";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";

type M2Product = {
  sku: string;
  name: string;
  price: number;
  status: number;
  visibility: number;
  extension_attributes?: { category_links?: { category_id: string }[] };
};

export default function ProductsPage() {
  const [q, setQ] = useState("TEST");
  const [rows, setRows] = useState<M2Product[]>([]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState("");

  const load = async () => {
    setLoading(true); setErr("");
    try {
      const params = new URLSearchParams({ q, page: "1", size: "50" });
      const data = await api.get(`/ops/products/list?${params.toString()}`);
      setRows(data?.items ?? []);
    } catch (e:any) { setErr(e.message || "Feil"); }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); /* eslint-disable-next-line */ }, []);

  const items = useMemo(() => rows ?? [], [rows]);

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">📦 Produkter</h1>

      <div className="flex gap-2">
        <input
          className="border rounded-lg px-3 py-2 w-80"
          placeholder="Søk (sku/navn)…"
          value={q}
          onChange={(e)=>setQ(e.target.value)}
          onKeyDown={(e)=>{ if (e.key==="Enter") load(); }}
        />
        <button className="px-3 py-2 rounded-lg border hover:bg-black/5" onClick={load} disabled={loading}>
          {loading ? "Søker…" : "Søk"}
        </button>
        <Link className="px-3 py-2 rounded-lg border hover:bg-black/5" href="/m2">← Tilbake</Link>
      </div>

      {err && <div className="text-red-600 text-sm">{err}</div>}

      <div className="overflow-x-auto border rounded-xl">
        <table className="min-w-full text-sm">
          <thead className="bg-black/5">
            <tr>
              <th className="text-left p-2">SKU</th>
              <th className="text-left p-2">Navn</th>
              <th className="text-right p-2">Pris</th>
              <th className="text-left p-2">Vis</th>
              <th className="text-left p-2">Cats</th>
              <th className="text-left p-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {items.map(p => {
              const cats = p.extension_attributes?.category_links?.map(c=>c.category_id).join(",") || "";
              return (
                <tr key={p.sku} className="border-t">
                  <td className="p-2 font-mono">{p.sku}</td>
                  <td className="p-2">{p.name}</td>
                  <td className="p-2 text-right">{p.price}</td>
                  <td className="p-2">{p.visibility}</td>
                  <td className="p-2">{cats || <span className="text-gray-400">–</span>}</td>
                  <td className="p-2">
                    <Link className="px-2 py-1 rounded border hover:bg-black/5"
                      href={`/m2/categories?sku=${encodeURIComponent(p.sku)}&cats=${encodeURIComponent(cats)}`}>
                      Map categories
                    </Link>
                  </td>
                </tr>
              );
            })}
            {!items.length && (
              <tr><td className="p-4 text-gray-500" colSpan={6}>Ingen treff.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
TSX
echo "✅ Skrev /app/m2/products/page.tsx"

# 5) /m2/categories – enkel editor som kaller gateway replace
cat > "${ADMIN_DIR}/app/m2/categories/page.tsx" <<'TSX'
"use client";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { api } from "@/lib/api";

export default function CategoryEditPage() {
  const sp = useSearchParams();
  const sku = sp.get("sku") || "";
  const preset = sp.get("cats") || "";
  const [cats, setCats] = useState(preset);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<string>("");

  useEffect(() => { setCats(preset); }, [preset]);

  const parsed = useMemo(() => {
    return cats
      .split(/[,\s;]+/)
      .map(s => s.trim())
      .filter(Boolean)
      .filter(s => /^[0-9]+$/.test(s))
      .map(s => Number(s));
  }, [cats]);

  const save = async () => {
    setSaving(true); setMsg("");
    try {
      if (!sku) throw new Error("Mangler SKU");
      const body = { items: [{ sku, categoryIds: parsed }] };
      const res = await api.post("/ops/category/replace", body);
      if (res?.ok) setMsg("✅ Lagret!");
      else throw new Error(res?.error || "Ukjent feil");
    } catch (e:any) {
      setMsg(`❌ ${e.message || e}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">🗂 Category mapper</h1>
      <div className="flex items-center gap-2">
        <Link className="px-3 py-2 rounded-lg border hover:bg-black/5" href="/m2/products">← Produkter</Link>
        <Link className="px-3 py-2 rounded-lg border hover:bg-black/5" href="/m2">Hjem</Link>
      </div>

      <div className="p-4 rounded-xl border space-y-3 max-w-xl">
        <div className="text-sm text-gray-600">SKU</div>
        <input className="border rounded-lg px-3 py-2 w-full font-mono bg-black/5" value={sku} readOnly />

        <div className="text-sm text-gray-600">Category IDs (komma-separert)</div>
        <input
          className="border rounded-lg px-3 py-2 w-full"
          placeholder="f.eks 2,4,7"
          value={cats}
          onChange={(e)=>setCats(e.target.value)}
        />

        <div className="text-xs text-gray-500">
          Parser til: [{parsed.join(", ")}]
        </div>

        <button className="px-3 py-2 rounded-lg border hover:bg-black/5" onClick={save} disabled={saving}>
          {saving ? "Lagrer…" : "Lagre (replace)"}
        </button>

        {msg && <div className="text-sm">{msg}</div>}
      </div>
    </div>
  );
}
TSX
echo "✅ Skrev /app/m2/categories/page.tsx"

echo "🚀 Ferdig! Start/refresh admin på http://localhost:3000/m2"