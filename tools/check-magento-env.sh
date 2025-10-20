#!/usr/bin/env bash
set -euo pipefail

say(){ printf "%b\n" "→ $*"; }
ok(){ printf "%b\n" "✓ $*"; }
warn(){ printf "%b\n" "⚠ $*"; }

ROOT="$(pwd)"
ENV="$ROOT/.env.local"

say "Prosjektrot: $ROOT"

# 1) Vis / opprett .env.local
if [ ! -f "$ENV" ]; then
  warn "Fant ikke .env.local – oppretter tom fil."
  touch "$ENV"
fi

say "Innhold i .env.local (maskerer tokens i output):"
# Maskér lange tokens i utskrift for trygg lesing
awk '
  BEGIN{ FS="=" }
  /^[[:space:]]*$/ { next } 
  /^[#]/ { print; next }
  { 
    key=$1; val=$0; sub(/^[^=]*=/,"",val)
    if (key ~ /TOKEN/) { if (length(val)>8) val=substr(val,1,4)"****"substr(val,length(val)-3,4) }
    print key"="val
  }
' "$ENV" || true
echo

# 2) Sikre at nøklene finnes
grep -q '^MAGENTO_BASE_URL=' "$ENV" || echo 'MAGENTO_BASE_URL=' >> "$ENV"
grep -q '^MAGENTO_ADMIN_TOKEN=' "$ENV" || echo 'MAGENTO_ADMIN_TOKEN=' >> "$ENV"
grep -q '^PRICE_MULTIPLIER=' "$ENV" || echo 'PRICE_MULTIPLIER=1' >> "$ENV"

# 3) Debug-route for å se hva serveren faktisk leser
DBG_DIR="$ROOT/app/api/_debug/env"
mkdir -p "$DBG_DIR"
cat > "$DBG_DIR/route.ts" <<'TS'
import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'

export async function GET() {
  // NB: Dette kjøres kun på serveren
  const keys = ['MAGENTO_BASE_URL','MAGENTO_ADMIN_TOKEN','PRICE_MULTIPLIER','NODE_ENV']
  const out: Record<string,string> = {}
  for (const k of keys) {
    const v = process.env[k]
    if (v == null) out[k] = '(missing)'
    else if (/TOKEN/i.test(k) && v.length>8) out[k] = v.slice(0,4)+'****'+v.slice(-4)
    else out[k] = v
  }
  return NextResponse.json(out)
}
TS
ok "La inn debug-endepunkt: /api/_debug/env"

# 4) Rydd Next-cache
say "Rydder .next/.next-cache"
rm -rf .next .next-cache 2>/dev/null || true

ok "Ferdig. Nå: stopp dev-server, sett riktige verdier i .env.local og start på nytt."
echo
echo "Sjekk deretter:  curl -s http://localhost:3000/api/_debug/env"