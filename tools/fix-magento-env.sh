#!/usr/bin/env bash
set -euo pipefail

say(){ printf "%b\n" "→ $*"; }
ok(){ printf "%b\n" "✓ $*"; }
warn(){ printf "%b\n" "⚠ $*"; }

ENV=".env.local"
MAGENTO_TS="src/lib/magento.ts"

# 1) Sikre .env.local
if [ ! -f "$ENV" ]; then
  say "Oppretter $ENV"
  touch "$ENV"
fi

# Hent eksisterende verdier (om noen) – både nye og gamle nøkkelnavn:
getval(){ grep -E "^$1=" "$ENV" | sed -E "s/^$1=//" || true; }

MBU="$(getval MAGENTO_BASE_URL)"
MAT="$(getval MAGENTO_ADMIN_TOKEN)"
OLD_URL="$(getval MAGENTO_URL)"
OLD_TOK="$(getval MAGENTO_TOKEN)"
PMULT="$(getval PRICE_MULTIPLIER)"

# Migrér ev. gamle nøkler
if [ -z "${MBU:-}" ] && [ -n "${OLD_URL:-}" ]; then
  echo "MAGENTO_BASE_URL=$OLD_URL" >> "$ENV"
  MBU="$OLD_URL"
  warn "Fant MAGENTO_URL – kopierte til MAGENTO_BASE_URL"
fi
if [ -z "${MAT:-}" ] && [ -n "${OLD_TOK:-}" ]; then
  echo "MAGENTO_ADMIN_TOKEN=$OLD_TOK" >> "$ENV"
  MAT="$OLD_TOK"
  warn "Fant MAGENTO_TOKEN – kopierte til MAGENTO_ADMIN_TOKEN"
fi

# Sørg for at nøkler finnes (la verdi stå tom hvis du ikke vet den her)
grep -q '^MAGENTO_BASE_URL=' "$ENV" || echo 'MAGENTO_BASE_URL=' >> "$ENV"
grep -q '^MAGENTO_ADMIN_TOKEN=' "$ENV" || echo 'MAGENTO_ADMIN_TOKEN=' >> "$ENV"
grep -q '^PRICE_MULTIPLIER=' "$ENV" || echo 'PRICE_MULTIPLIER=1' >> "$ENV"

say "Sjekk at .env.local har riktige verdier:"
grep -E '^(MAGENTO_BASE_URL|MAGENTO_ADMIN_TOKEN|PRICE_MULTIPLIER)=' "$ENV" || true
echo

# 2) Patch src/lib/magento.ts til lazy env-sjekk (ingen throw ved import)
mkdir -p "$(dirname "$MAGENTO_TS")"

cat > "$MAGENTO_TS" <<'TS'
let BASE = process.env.MAGENTO_BASE_URL || ''
let TOKEN = process.env.MAGENTO_ADMIN_TOKEN || ''

function ensureEnv() {
  BASE = process.env.MAGENTO_BASE_URL || BASE
  TOKEN = process.env.MAGENTO_ADMIN_TOKEN || TOKEN
  if (!BASE || !TOKEN) {
    throw new Error('Missing MAGENTO_BASE_URL or MAGENTO_ADMIN_TOKEN in environment')
  }
}

async function handle<T>(res: Response, verb: string, path: string): Promise<T> {
  if (!res.ok) {
    const text = await res.text().catch(() => '')
    throw new Error(`Magento ${verb} ${path} -> ${res.status} ${text}`)
  }
  return res.json() as Promise<T>
}

function authHeaders(): HeadersInit {
  ensureEnv()
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${TOKEN}`,
  }
}

export async function mgGet<T>(path: string) {
  const headers = authHeaders()
  const res = await fetch(`${BASE}${path}`, { headers, cache: 'no-store' })
  return handle<T>(res, 'GET', path)
}

export async function mgPost<T>(path: string, body?: any) {
  const headers = authHeaders()
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers,
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  })
  return handle<T>(res, 'POST', path)
}

export async function mgPut<T>(path: string, body?: any) {
  const headers = authHeaders()
  const res = await fetch(`${BASE}${path}`, {
    method: 'PUT',
    headers,
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  })
  return handle<T>(res, 'PUT', path)
}
TS

ok "Patchet $MAGENTO_TS"

# 3) Rydd Next-cache (for å plukke opp env-endringer og patch)
say "Rydder .next-cache"
rm -rf .next 2>/dev/null || true
rm -rf .next-cache 2>/dev/null || true

ok "Ferdig. Start dev-server på nytt (npm run dev / yarn dev / pnpm dev)."
echo
echo "Tips:"
echo "  - Sett MAGENTO_BASE_URL uten trailing slash, f.eks: https://your-magento.tld/rest"
echo "  - Lim inn admin token i MAGENTO_ADMIN_TOKEN"
echo "  - Juster PRICE_MULTIPLIER=1.15 for påslag i backend"