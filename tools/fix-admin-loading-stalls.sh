#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"

echo "→ Oppretter mapper…"
mkdir -p "$ROOT/src/lib"
mkdir -p "$ROOT/app/admin/products"
mkdir -p "$ROOT/app/admin/orders"
mkdir -p "$ROOT/app/admin/customers"

SAFE_FETCH="$ROOT/src/lib/safe-fetch.ts"
echo "→ Skriver $SAFE_FETCH"
cat > "$SAFE_FETCH" <<'TS'
// Enkel, robust fetch med timeout + JSON-parsing + gode feil
export async function safeFetchJSON<T>(
  input: RequestInfo | URL,
  init: RequestInit & { timeoutMs?: number } = {}
): Promise<{ data?: T; error?: string; status: number }> {
  const { timeoutMs = 15000, ...rest } = init
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), timeoutMs)
  try {
    const res = await fetch(input, {
      cache: 'no-store',
      ...rest,
      signal: ctrl.signal,
      headers: {
        'accept': 'application/json, text/plain, */*',
        ...(rest.headers || {}),
      },
    })
    const status = res.status
    const text = await res.text()
    // Prøv JSON, men ikke kast feil hvis det ikke er gyldig
    let json: any = undefined
    try { json = text ? JSON.parse(text) : undefined } catch {}
    if (!res.ok) {
      return { error: (json && (json.error || json.message)) || `HTTP ${status}`, status }
    }
    return { data: json as T, status }
  } catch (e:any) {
    if (e?.name === 'AbortError') return { error: 'Timeout', status: 0 }
    return { error: e?.message || 'Ukjent feil', status: 0 }
  } finally {
    clearTimeout(t)
  }
}
TS

# Små helpers for å bygge listesider
build_client_page () {
  local OUTFILE="$1"
  local TITLE="$2"
  local API_PATH="$3"
  local RENDER_ROW="$4" # TSX for render av rad
  local TYPE_IMPORT="$5" # ev. types

  cat > "$OUTFILE" <<TSX
'use client'
import React from 'react'
import { AdminPage } from '@/src/components/AdminPage'
import { safeFetchJSON } from '@/src/lib/safe-fetch'
${TYPE_IMPORT}

export default function Page(){
  const [busy, setBusy] = React.useState(true)
  const [error, setError] = React.useState<string|undefined>(undefined)
  const [rows, setRows] = React.useState<any[]>([])

  React.useEffect(() => {
    let mounted = true
    const run = async () => {
      setBusy(true)
      setError(undefined)
      const { data, error } = await safeFetchJSON<any[]>('${API_PATH}')
      if (!mounted) return
      if (error) setError(error)
      setRows(data || [])
      setBusy(false)
    }

    // Watchdog: hvis noe går galt og vi ikke havner i finally, avpubliser busy etter 20s
    const watchdog = setTimeout(() => mounted && setBusy(false), 20000)
    run()
    return () => { mounted = false; clearTimeout(watchdog) }
  }, [])

  return (
    <AdminPage title="${TITLE}">
      {busy && <div className="p-6 text-sm text-neutral-500">Loading…</div>}
      {!busy && error && (
        <div className="p-6 text-sm text-red-600">Kunne ikke laste: {error}</div>
      )}
      {!busy && !error && rows.length === 0 && (
        <div className="p-6 text-sm text-neutral-500">Ingen funn.</div>
      )}
      {!busy && !error && rows.length > 0 && (
        <div className="p-4">
          <div className="overflow-auto border rounded">
            <table className="min-w-full text-sm">
              <thead className="bg-neutral-50 text-neutral-600">
                <tr>
                  ${RENDER_ROW//<TR/>/<TH/>}
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((r, i) => (
                  <tr key={r.id || r._id || i} className="hover:bg-neutral-50">
                    ${RENDER_ROW//<TR/>/<TD/>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </AdminPage>
  )
}
TSX
}

# Produkter
PROD_PAGE="$ROOT/app/admin/products/page.tsx"
echo "→ Patcher $PROD_PAGE"
build_client_page "$PROD_PAGE" "Products" "/api/products?page=1&size=50" \
"<TR/><TR/><TR/><TR/>
<TH/>ID</TH>
<TH/>Name</TH>
<TH/>SKU</TH>
<TH/>Stock</TH>" \
""
# Erstatt TR/TB helpers med faktiske celler
perl -i -pe "s#<TD/>ID</TH>#<th className=\"text-left p-2\">ID</th>#g" "$PROD_PAGE"
perl -i -pe "s#<TD/>Name</TH>#<th className=\"text-left p-2\">Name</th>#g" "$PROD_PAGE"
perl -i -pe "s#<TD/>SKU</TH>#<th className=\"text-left p-2\">SKU</th>#g" "$PROD_PAGE"
perl -i -pe "s#<TD/>Stock</TH>#<th className=\"text-left p-2\">Stock</th>#g" "$PROD_PAGE"

perl -i -pe "s#<TD/>ID</TH>#<th className=\"text-left p-2\">ID</th>#g" "$PROD_PAGE"
perl -i -pe "s#<TH/>ID</TH>#<th className=\"text-left p-2\">ID</th>#g" "$PROD_PAGE"

perl -i -pe "s#<TR/>#<th className=\"text-left p-2\"></th>#g" "$PROD_PAGE"
perl -i -pe "s#<TH/>#<th className=\"text-left p-2\">#g" "$PROD_PAGE"
perl -i -pe "s#</TH>#</th>#g" "$PROD_PAGE"

perl -i -pe "s#<TD/>#<td className=\"p-2\">#g" "$PROD_PAGE"

# Bytt ut body-rendring (r som produkt)
perl -i -pe "s#\\{rows.map\\(\\(r, i\\) => \\(#\\{rows.map\\(\\(r:any, i:number\\) => \\(#g" "$PROD_PAGE"
perl -i -pe "s#<td className=\"p-2\">\\</td>#<td className=\"p-2\">\\{r.id||r._id||'-'\\}</td># if $.>=1" "$PROD_PAGE"
perl -i -pe "s#</tr>\\n\\s*\\)\\)}#<td className=\"p-2\">\\{r.name||'-'\\}</td><td className=\"p-2\">\\{r.sku||'-'\\}</td><td className=\"p-2\">\\{r.stock??r.inventory??'-'\\}</td></tr>\\n      )}#g" "$PROD_PAGE"

# Ordre
ORD_PAGE="$ROOT/app/admin/orders/page.tsx"
echo "→ Patcher $ORD_PAGE"
build_client_page "$ORD_PAGE" "Orders" "/api/orders" \
"<TR/><TR/><TR/><TR/>
<TH/>Order ID</TH>
<TH/>Date</TH>
<TH/>Customer</TH>
<TH/>Lines</TH>" \
""
perl -i -pe "s#<TR/>#<th className=\"text-left p-2\"></th>#g" "$ORD_PAGE"
perl -i -pe "s#<TH/>#<th className=\"text-left p-2\">#g" "$ORD_PAGE"
perl -i -pe "s#</TH>#</th>#g" "$ORD_PAGE"
perl -i -pe "s#<TD/>#<td className=\"p-2\">#g" "$ORD_PAGE"
perl -i -pe "s#\\{rows.map\\(\\(r, i\\) => \\(#\\{rows.map\\(\\(r:any, i:number\\) => \\(#g" "$ORD_PAGE"
perl -i -pe "s#<td className=\"p-2\">\\</td>#<td className=\"p-2\">\\{r.id||r._id||'-'\\}</td># if $.>=1" "$ORD_PAGE"
perl -i -pe "s#</tr>\\n\\s*\\)\\)}#<td className=\"p-2\">\\{new Date(r.createdAt||r.date||Date.now\\(\\)).toLocaleString\\(\\)\\}</td><td className=\"p-2\">\\{r.customer?.name||r.customer?.email||'-'\\}</td><td className=\"p-2\">\\{Array.isArray\\(r.lines\\)?r.lines.length:0\\}</td></tr>\\n      )}#g" "$ORD_PAGE"

# Kunder
CUS_PAGE="$ROOT/app/admin/customers/page.tsx"
echo "→ Patcher $CUS_PAGE"
build_client_page "$CUS_PAGE" "Customers" "/api/customers" \
"<TR/><TR/><TR/>
<TH/>ID</TH>
<TH/>Name</TH>
<TH/>Email</TH>" \
""
perl -i -pe "s#<TR/>#<th className=\"text-left p-2\"></th>#g" "$CUS_PAGE"
perl -i -pe "s#<TH/>#<th className=\"text-left p-2\">#g" "$CUS_PAGE"
perl -i -pe "s#</TH>#</th>#g" "$CUS_PAGE"
perl -i -pe "s#<TD/>#<td className=\"p-2\">#g" "$CUS_PAGE"
perl -i -pe "s#\\{rows.map\\(\\(r, i\\) => \\(#\\{rows.map\\(\\(r:any, i:number\\) => \\(#g" "$CUS_PAGE"
perl -i -pe "s#<td className=\"p-2\">\\</td>#<td className=\"p-2\">\\{r.id||r._id||'-'\\}</td># if $.>=1" "$CUS_PAGE"
perl -i -pe "s#</tr>\\n\\s*\\)\\)}#<td className=\"p-2\">\\{r.name||'-'\\}</td><td className=\"p-2\">\\{r.email||'-'\\}</td></tr>\\n      )}#g" "$CUS_PAGE"

echo "→ Rydder .next-cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

echo "✓ Ferdig. Start dev-server på nytt (npm run dev)."