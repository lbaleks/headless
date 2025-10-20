#!/usr/bin/env bash
set -euo pipefail

say(){ printf "%b\n" "→ $*"; }
ok(){ printf "%b\n" "✓ $*"; }

ENV=".env.local"
DBG="app/api/_debug/env/route.ts"

# --- 1) Sikre miljøfil og rette nøkler ---
say "Validerer $ENV"
if [ ! -f "$ENV" ]; then
  say "Oppretter .env.local"
  touch "$ENV"
fi

# Hent eksisterende verdier
MBU=$(grep -E '^MAGENTO_BASE_URL=' "$ENV" | cut -d= -f2- || true)
MAT=$(grep -E '^MAGENTO_ADMIN_TOKEN=' "$ENV" | cut -d= -f2- || true)
M2T=$(grep -E '^M2_TOKEN=' "$ENV" | cut -d= -f2- || true)

# Kopier M2_TOKEN hvis mangler
if [ -z "${MAT:-}" ] && [ -n "${M2T:-}" ]; then
  echo "MAGENTO_ADMIN_TOKEN=$M2T" >> "$ENV"
  ok "La til MAGENTO_ADMIN_TOKEN fra M2_TOKEN"
fi

# Sørg for multiplier
grep -q '^PRICE_MULTIPLIER=' "$ENV" || echo 'PRICE_MULTIPLIER=1' >> "$ENV"

say "Oppdatert .env.local:"
grep -E 'MAGENTO_|PRICE_MULTIPLIER' "$ENV" || true
echo

# --- 2) Debug-rute for /api/_debug/env ---
say "Oppretter debug-endepunkt for miljøvariabler"
mkdir -p "$(dirname "$DBG")"
cat > "$DBG" <<'TS'
import { NextResponse } from 'next/server'
export const dynamic = 'force-dynamic'
export async function GET() {
  const keys = ['MAGENTO_BASE_URL','MAGENTO_ADMIN_TOKEN','NEXT_PUBLIC_GATEWAY_BASE','M2_BASIC','PRICE_MULTIPLIER','NODE_ENV']
  const out: Record<string,string> = {}
  for (const k of keys) {
    const v = process.env[k]
    if (!v) out[k] = '(missing)'
    else if (/TOKEN|BASIC/i.test(k) && v.length>8) out[k] = v.slice(0,4)+'****'+v.slice(-4)
    else out[k] = v
  }
  return NextResponse.json(out)
}
TS
ok "La inn $DBG"

# --- 3) Rydd cache ---
say "Rydder .next og .next-cache"
rm -rf .next .next-cache 2>/dev/null || true

ok "Ferdig!"
echo
echo "👉  Nå kan du starte dev-server på nytt:"
echo "    npm run dev"
echo
echo "Deretter åpner du http://localhost:3000/api/_debug/env"
echo "for å bekrefte at variablene lastes korrekt."