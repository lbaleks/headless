#!/usr/bin/env bash
set -euo pipefail

root_dir="$(pwd)"

banner() { printf "\n\033[1;36m→ %s\033[0m\n" "$*"; }
info()   { printf "  • %s\n" "$*"; }
ok()     { printf "  ✓ %s\n" "$*"; }
warn()   { printf "  ⚠ %s\n" "$*"; }

# --- 0) Sjekk at vi står i Next-prosjektet ---
if [ ! -f "package.json" ] || [ ! -d "app" ]; then
  echo "Kjør meg fra prosjektroten (der package.json ligger)."
  exit 1
fi

# --- 1) DELETE /api/products/[id] (fjerner lokal override) ---
banner "Installerer/oppdaterer DELETE /api/products/[id]…"
mkdir -p app/api/products/\[id]

API_FILE="app/api/products/[id]/route.ts"
if [ ! -f "$API_FILE" ]; then
  cat > "$API_FILE" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')

async function readStore(): Promise<any[]> {
  try {
    const j = JSON.parse(await fs.readFile(DEV_FILE, 'utf8'))
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch { return [] }
}
async function writeStore(items: any[]) {
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}

export async function DELETE(_: Request, ctx: { params: { id: string } }) {
  const idOrSku = decodeURIComponent(ctx.params.id)
  const toLower = String(idOrSku).toLowerCase()
  const items = await readStore()
  const before = items.length
  const filtered = items.filter(p =>
    String(p.sku).toLowerCase() !== toLower &&
    String(p.id ?? '').toLowerCase() !== toLower
  )
  await writeStore(filtered)
  const removed = before - filtered.length
  return NextResponse.json({ ok: true, removed })
}
TS
  ok "Opprettet $API_FILE"
else
  # Legg til DELETE-blokk hvis den mangler
  if ! grep -q "export async function DELETE" "$API_FILE"; then
    cat >> "$API_FILE" <<'TS'

export async function DELETE(_: Request, ctx: { params: { id: string } }) {
  const idOrSku = decodeURIComponent(ctx.params.id)
  const toLower = String(idOrSku).toLowerCase()
  const items = await readStore()
  const before = items.length
  const filtered = items.filter(p =>
    String(p.sku).toLowerCase() !== toLower &&
    String(p.id ?? '').toLowerCase() !== toLower
  )
  await writeStore(filtered)
  const removed = before - filtered.length
  return NextResponse.json({ ok: true, removed })
}
TS
    ok "La til DELETE-handler i $API_FILE"
  else
    info "DELETE-handler finnes allerede – hopper over."
  fi
fi

# --- 2) Lag SourceBadge-komponent ---
banner "Installerer SourceBadge-komponent…"
mkdir -p src/components
SB="src/components/SourceBadge.tsx"
if [ ! -f "$SB" ]; then
  cat > "$SB" <<'TSX'
export function SourceBadge({ source }: { source?: string }) {
  const c =
    source === 'magento' ? 'bg-indigo-100 text-indigo-700' :
    source === 'local-override' ? 'bg-amber-100 text-amber-700' :
    source === 'local-stub' ? 'bg-rose-100 text-rose-700' :
    'bg-neutral-100 text-neutral-600'
  return <span className={`inline-block rounded px-2 py-0.5 text-xs ${c}`}>{source || 'unknown'}</span>
}
TSX
  ok "Opprettet $SB"
else
  info "SourceBadge finnes allerede – hopper over."
fi

# --- 3) Patcher admin/products/page.tsx til å bruke merged + badge + “Fjern override” ---
banner "Patcher app/admin/products/page.tsx…"
APP_P="app/admin/products/page.tsx"
if [ ! -f "$APP_P" ]; then
  warn "Fant ikke $APP_P – hopper over UI-patch for products."
else
  node - <<'NODE'
const fs = require('fs');
const p = 'app/admin/products/page.tsx';
let src = fs.readFileSync(p, 'utf8');
let changed = false;

// A) bruk merged-endepunkt
{
  const before1 = `/api/products?page=`;
  const before2 = '`/api/products?page=${page}&size=${size}${q ? `&q=${encodeURIComponent(q)}` : \'\'}`';
  const repl   = '`/api/products/merged?page=${page}&size=${size}${q ? `&q=${encodeURIComponent(q)}` : \'\'}`';
  if (src.includes(before1) && !src.includes('/api/products/merged')) {
    src = src.replace(/`\/api\/products\?page=\$\{page\}&size=\$\{size\}\$\{q \? `&q=\$\{encodeURIComponent\(q\)\}` : ''\}`/g, repl);
    changed = true;
  } else if (!src.includes('/api/products/merged') && src.includes('/api/products?page=')) {
    src = src.replace('/api/products?page=', '/api/products/merged?page=');
    changed = true;
  }
}

// B) importer SourceBadge
if (!src.includes(`from '@/src/components/SourceBadge'`)) {
  src = src.replace(/(^import .+\n)(?!.*SourceBadge)/m, m => m + `import { SourceBadge } from '@/src/components/SourceBadge'\n`);
  changed = true;
}

// C) vis badge ved navn hvis mulig
if (src.includes('{item.name') && !src.includes('<SourceBadge')) {
  src = src.replace(/\{item\.name[^\}]*\}/, match => {
    return `<span className="inline-flex items-center gap-2">${match}<SourceBadge source={item.source} /></span>`;
  });
  changed = true;
}

// D) “Fjern override”-knapp hvis source != magento
if (!src.includes('clearOverride(')) {
  src = src.replace(/export default function [A-Za-z0-9_]+\([^\)]*\)\s*\{/, m => m + `
  async function clearOverride(sku: string) {
    await fetch(\`/api/products/\${encodeURIComponent(sku)}\`, { method: 'DELETE' })
    if (typeof window !== 'undefined') {
      // enkel refresh hvis SWR ikke er i bruk
      try { (window as any).location?.reload() } catch {}
    }
  }
`);
  changed = true;
}
if (src.includes('<td') && src.includes('item.sku') && !src.includes('Fjern override')) {
  // legg en ekstra action-td på slutten av raden
  src = src.replace(/<\/tr>\s*\)\s*}(\))?/m, match => `
    <td className="p-2">
      {item.source && item.source !== 'magento' ? (
        <button
          onClick={() => clearOverride(item.sku)}
          className="rounded border px-2 py-1 text-xs hover:bg-neutral-50"
          title="Fjern lokal override"
        >
          Fjern override
        </button>
      ) : <span className="text-neutral-400 text-xs">—</span>}
    </td>
  </tr>
)}${match.endsWith(')') ? '' : ''}`);
  changed = true;
}

if (changed) fs.writeFileSync(p, src);
console.log(changed ? '  ✓ Patchet products/page.tsx' : '  • Ingen endringer nødvendig i products/page.tsx');
NODE
fi

# --- 4) SyncNow-knapp i admin/layout.tsx ---
banner "Legger til ‘Sync nå’-knapp i admin/layout…"
LAY="app/admin/layout.tsx"
mkdir -p "$(dirname "$LAY")"
if [ -f "$LAY" ]; then
  node - <<'NODE'
const fs = require('fs');
const p = 'app/admin/layout.tsx';
let src = fs.readFileSync(p, 'utf8');
let changed = false;

// A) inline SyncNow komponent hvis ikke finnes
if (!src.includes('function SyncNow(')) {
  src = src.replace(/export default function RootLayout[^{]+\{/, m => `${m}
  function SyncNow() {
    const [busy, setBusy] = React.useState(false)
    return (
      <button
        disabled={busy}
        onClick={async () => {
          setBusy(true)
          await fetch('/api/jobs/run-sync', { method: 'POST' })
          setBusy(false)
        }}
        className="ml-2 rounded bg-neutral-900 px-3 py-1.5 text-white text-sm disabled:opacity-50"
      >
        {busy ? 'Synker…' : 'Sync nå'}
      </button>
    )
  }
`);
  changed = true;
}

// B) importer React hvis nødvendig
if (!/import\s+\*\s+as\s+React\s+from\s+'react'/.test(src) && !/from 'react'/.test(src)) {
  src = `import * as React from 'react'\n` + src;
  changed = true;
}

// C) plasser <SyncNow /> ved siden av <JobsFooter /> hvis mulig
if (src.includes('<JobsFooter />') && !src.includes('<SyncNow />')) {
  src = src.replace('<JobsFooter />', '<JobsFooter /><SyncNow />');
  changed = true;
}

if (changed) fs.writeFileSync(p, src);
console.log(changed ? '  ✓ Patchet admin/layout.tsx' : '  • Ingen endringer nødvendig i admin/layout.tsx');
NODE
else
  warn "Fant ikke $LAY – hopper over layout-patch."
fi

# --- 5) Oppsummer små test-kommandoer ---
banner "Klart! Kjør testene under:"
cat <<'TXT'
# 1) Seed litt lokalt og se at merged tar dem med
curl -s -X POST 'http://localhost:3000/api/products/seed?n=3' | jq .
curl -s 'http://localhost:3000/api/products/merged?page=1&size=5' | jq '.total,(.items[0]//{})'

# 2) Fjern override for TEST (skal falle tilbake til Magento)
curl -s -X DELETE 'http://localhost:3000/api/products/TEST' | jq .
curl -s 'http://localhost:3000/api/products/TEST' | jq '.sku,.price,.name,.source'

# 3) Kjør en full sync-jobb fra UI-knappen (nederst) eller via API:
curl -s -X POST 'http://localhost:3000/api/jobs/run-sync' | jq '.id,.counts'
TXT

ok "Autoinstall fullført."