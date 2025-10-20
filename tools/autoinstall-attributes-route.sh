#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

ROOT="${PWD}"
BASE="${BASE:-http://localhost:3000}"

# --- 1) Sørg for mapper --------------------------------------------------------
log "Oppretter mapper for attributes-api"
mkdir -p "app/api/products/attributes/[sku]"

# --- 2) Skriv dynamisk route: /api/products/attributes/[sku] ------------------
log "Skriver app/api/products/attributes/[sku]/route.ts"
cat > "app/api/products/attributes/[sku]/route.ts" <<'TS'
import { NextResponse } from 'next/server';
import fs from 'fs/promises';
import path from 'path';

export const dynamic = 'force-dynamic';

export async function GET(
  _req: Request,
  ctx: { params: { sku: string } }
) {
  try {
    const sku = decodeURIComponent(ctx.params.sku);
    const file = path.join(process.cwd(), 'var', 'attributes', `${sku}.json`);

    let attributes: any = {};
    try {
      const raw = await fs.readFile(file, 'utf8');
      attributes = JSON.parse(raw);
    } catch {
      attributes = {};
    }

    return NextResponse.json({ ok: true, sku, attributes });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, error: String(err?.message || err) },
      { status: 500 }
    );
  }
}
TS

# --- 3) (Valgfritt) Skriv fallback /api/products/attributes?sku=… -------------
log "Skriver app/api/products/attributes/route.ts (fallback til [sku])"
mkdir -p "app/api/products/attributes"
cat > "app/api/products/attributes/route.ts" <<'TS'
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function GET(req: Request) {
  const url = new URL(req.url);
  const sku = url.searchParams.get('sku');
  if (!sku) {
    return NextResponse.json({ ok: false, error: 'missing sku' }, { status: 400 });
  }
  // Redirect til den kanoniske dynamiske ruta
  return NextResponse.redirect(new URL(`/api/products/attributes/${encodeURIComponent(sku)}`, req.url));
}
TS

# --- 4) Rydd opp i mulige slug-konflikter -------------------------------------
log "Sjekker for slug-konflikter i app/api/products/attributes/*"
conflicts=$(find app/api/products/attributes -maxdepth 1 -type d -name '[[]*[]]' -not -name '[sku]' || true)
if [ -n "$conflicts" ]; then
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    if [[ "$d" != *"[sku]"* ]]; then
      log "Fjerner/erstatter konflikt: $d"
      rm -rf "$d"
    fi
  done <<< "$conflicts"
fi

# --- 5) Restart dev (rydder port) ---------------------------------------------
log "Restart dev (rydder port :3000)"
lsof -ti :3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
# Start dev i bakgrunnen (stille)
if [ -f package.json ]; then
  ( npm run dev --silent >/dev/null 2>&1 & echo $! > /tmp/next.dev.pid ) || true
else
  log "Advarsel: fant ikke package.json – hopper over dev-start"
fi

# --- 6) Vent til server svarer -------------------------------------------------
log "Venter på at server svarer…"
deadline=$((SECONDS+15))
ok=0
while [ $SECONDS -lt $deadline ]; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/debug/health" || true)
  if [ "$code" = "200" ] || [ "$code" = "204" ]; then ok=1; break; fi
  sleep 0.5
done
if [ $ok -ne 1 ]; then
  log "Health svarte ikke – fortsetter likevel (kan være uten health-route)."
fi

# --- 7) Verifiser dynamic path -------------------------------------------------
log "Verifiser dynamisk path: /api/products/attributes/TEST"
curl -sS -D- "$BASE/api/products/attributes/TEST" -o /tmp/attr_resp.json | head -n1
mime=$(file -b --mime-type /tmp/attr_resp.json || true)
log "MIME: $mime"
head -c 200 /tmp/attr_resp.json | cat
echo

if [ "$mime" != "application/json" ]; then
  log "::WARN:: respons er ikke application/json (kan være hot-reload-lag)"
fi

# --- 8) (Bonus) Verifiser fallback -------------------------------------------
log "Verifiser fallback: /api/products/attributes?sku=TEST"
curl -sS -D- "$BASE/api/products/attributes?sku=TEST" -o /tmp/attr_fallback.json | head -n1 || true

log "Ferdig ✅  Bruk:"
log "  • GET $BASE/api/products/attributes/TEST"
log "  • ELLER: $BASE/api/products/attributes?sku=TEST (redirect til dynamisk)"
