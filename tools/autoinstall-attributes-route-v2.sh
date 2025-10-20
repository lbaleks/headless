#!/usr/bin/env bash
set -euo pipefail

log(){ printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# --- 1) Normaliser mappestruktur: behold KUN [sku] ---
log "Sjekker dynamiske mapper under app/api/products/attributes"
mkdir -p app/api/products/attributes
if [ -d "app/api/products/attributes/[id]" ]; then
  log "Fant [id] → flytter innhold til [sku] og fjerner [id]"
  mkdir -p "app/api/products/attributes/[sku]"
  find "app/api/products/attributes/[id]" -type f -maxdepth 1 -print0 \
    | xargs -0 -I{} bash -lc 'bn=$(basename "{}"); \
      [ -f "app/api/products/attributes/[sku]/$bn" ] || mv "{}" "app/api/products/attributes/[sku]/$bn"'
  rm -rf "app/api/products/attributes/[id]"
fi
# Fjern andre dynamiske mapper som ikke heter [sku]
find app/api/products/attributes -maxdepth 1 -type d -name '[[]*[]]' -not -name '[sku]' -exec rm -rf {} + || true
mkdir -p app/api/products/attributes/[sku]

# --- 2) Skriv robust [sku]/route.ts (idempotent) ---
cat > app/api/products/attributes/[sku]/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export async function GET(
  _req: Request,
  ctx: { params: { sku: string } }
) {
  const sku = (ctx?.params?.sku || '').trim()
  if (!sku) return NextResponse.json({ ok:false, error:'missing sku' }, { status: 400 })

  // attributes lagres som var/attributes/<SKU>.json av update-attributes
  const dir = path.join(process.cwd(), 'var', 'attributes')
  const file = path.join(dir, `${sku}.json`)
  let attributes: Record<string, any> = {}
  try {
    const data = await fs.readFile(file, 'utf8')
    attributes = JSON.parse(data)
  } catch {
    // tom attributes er ok
  }
  return NextResponse.json({ ok:true, sku, attributes })
}
TS

# --- 3) Skriv fallback route (/api/products/attributes?sku=...) (idempotent) ---
cat > app/api/products/attributes/route.ts <<'TS'
import { NextResponse } from 'next/server'

export async function GET(req: Request) {
  const q = new URL(req.url).searchParams
  const sku = (q.get('sku') || '').trim()
  if (!sku) return NextResponse.json({ ok:false, error:'missing sku' }, { status: 400 })
  // 302 til den dynamiske ruta
  return NextResponse.redirect(new URL(`./${encodeURIComponent(sku)}`, req.url), 302)
}
TS

# --- 4) Sikre health-route finnes (ny sti /api/debug/health) ---
mkdir -p app/api/debug/health
cat > app/api/debug/health/route.ts <<'TS'
import { NextResponse } from 'next/server'
export async function GET() { return NextResponse.json({ ok:true }) }
TS

# --- 5) Tøm Next cache + restart dev lydløst ---
log "Restart dev (rydder .next og port 3000)"
rm -rf .next
lsof -ti :3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
npm run dev --silent >/dev/null 2>&1 &

# liten vent for boot
sleep 1

# --- 6) Verifisering ---
BASE=${BASE:-http://localhost:3000}
log "Health-sjekk"
curl -sS "$BASE/api/debug/health" | jq -e '.ok==true' >/dev/null && log "Health OK" || log "::WARN:: Health feilet"

log "Henter attributes via dynamisk path"
code=$(curl -sS -w '%{http_code}' -D /tmp/attr.hdr -o /tmp/attr.json "$BASE/api/products/attributes/TEST" || true)
head -n1 /tmp/attr.hdr
mime=$(file -b --mime-type /tmp/attr.json 2>/dev/null || echo '')
if [ "$code" = "200" ] && [ "$mime" = "application/json" ]; then
  log "Attributes OK:"
  head -c 200 /tmp/attr.json; echo
else
  log "::WARN:: Unexpected response (code=$code mime=$mime)"
  head -c 200 /tmp/attr.json 2>/dev/null || true; echo
fi

log "Tester fallback (?sku=TEST)"
curl -sS -D - "$BASE/api/products/attributes?sku=TEST" -o /dev/null | head -n1 || true

log "Ferdig ✅"