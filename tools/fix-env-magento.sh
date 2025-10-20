#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
ENV_LOCAL="${ROOT}/.env.local"
ENV_FILE="${ROOT}/.env"

echo "→ Standardiserer Magento-env på ${ROOT}"

# --- Hjelpere ---
get_val () {
  # Henter første verdi for nøkkel i .env*. Tar høyde for mellomrom og sitat.
  local key="$1"; shift
  local file
  for file in "$@"; do
    [ -f "$file" ] || continue
    local line
    line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" || true)"
    if [ -n "$line" ]; then
      echo "$line" | sed -E 's/^[[:space:]]*[^=]+=[[:space:]]*//; s/^[\"\x27]//; s/[\"\x27][[:space:]]*$//'
      return 0
    fi
  done
  return 1
}

ensure_rest_suffix () {
  local base="$1"
  base="${base%/}"
  if [[ "$base" != *"/rest" ]]; then
    echo "${base}/rest"
  else
    echo "$base"
  fi
}

mask () {
  local s="$1"
  if [ -z "${s:-}" ]; then echo ""; return; fi
  local n=${#s}
  if [ $n -le 8 ]; then echo "***"; else echo "${s:0:8}…"; fi
}

# --- Les eksisterende verdier (prioritert rekkefølge) ---
BASE_URL="$( get_val MAGENTO_BASE_URL "$ENV_LOCAL" "$ENV_FILE" || true )"
[ -n "${BASE_URL:-}" ] || BASE_URL="$( get_val M2_BASE_URL "$ENV_LOCAL" "$ENV_FILE" || true )"
[ -n "${BASE_URL:-}" ] || BASE_URL="$( get_val NEXT_PUBLIC_GATEWAY_BASE "$ENV_LOCAL" "$ENV_FILE" || true )"

TOKEN="$( get_val MAGENTO_ADMIN_TOKEN "$ENV_LOCAL" "$ENV_FILE" || true )"
[ -n "${TOKEN:-}" ] || TOKEN="$( get_val M2_ADMIN_TOKEN "$ENV_LOCAL" "$ENV_FILE" || true )"
[ -n "${TOKEN:-}" ] || TOKEN="$( get_val M2_TOKEN "$ENV_LOCAL" "$ENV_FILE" || true )"

PRICE_MULTIPLIER="$( get_val PRICE_MULTIPLIER "$ENV_LOCAL" "$ENV_FILE" || true )"
M2_BASIC="$( get_val M2_BASIC "$ENV_LOCAL" "$ENV_FILE" || true )"

# --- Fallback: hent fra brukers eksempel i meldingen om det mangler (ikke ideelt, men praktisk) ---
# (ingen – vi baserer oss kun på filer)

# --- Normaliser BASE_URL ---
if [ -n "${BASE_URL:-}" ]; then
  BASE_URL="$(ensure_rest_suffix "$BASE_URL")"
fi

if [ -z "${BASE_URL:-}" ] || [ -z "${TOKEN:-}" ]; then
  echo "✗ Mangler BASE_URL eller TOKEN å skrive til .env.local"
  echo "  BASE_URL: ${BASE_URL:-<tom>}"
  echo "  TOKEN:    $(mask "${TOKEN:-}")"
  echo "  → Legg inn manuelt eller oppgi riktige nøkler i .env/.env.local (MAGENTO_BASE_URL / MAGENTO_ADMIN_TOKEN)"
  exit 1
fi

# --- Skriv .env.local konsolidert ---
echo "→ Skriver ${ENV_LOCAL}"
{
  echo "# --- Konsolidert av tools/fix-env-magento.sh ---"
  echo "MAGENTO_BASE_URL=${BASE_URL}"
  echo "MAGENTO_ADMIN_TOKEN=${TOKEN}"
  echo "NEXT_PUBLIC_GATEWAY_BASE=${BASE_URL}"
  [ -n "${PRICE_MULTIPLIER:-}" ] && echo "PRICE_MULTIPLIER=${PRICE_MULTIPLIER}"
  [ -n "${M2_BASIC:-}" ] && echo "M2_BASIC=${M2_BASIC}"
  echo
} > "${ENV_LOCAL}"

echo "  ✔ MAGENTO_BASE_URL = ${BASE_URL}"
echo "  ✔ MAGENTO_ADMIN_TOKEN = $(mask "${TOKEN}")"
[ -n "${PRICE_MULTIPLIER:-}" ] && echo "  ✔ PRICE_MULTIPLIER = ${PRICE_MULTIPLIER}"
[ -n "${M2_BASIC:-}" ] && echo "  ✔ M2_BASIC = (satt)"

# --- Sørg for debug-endpoint som returnerer JSON ---
mkdir -p app/api/_debug/env
cat > app/api/_debug/env/route.ts <<'TS'
import { NextResponse } from 'next/server';

export async function GET() {
  const rawBase =
    process.env.MAGENTO_BASE_URL ||
    process.env.M2_BASE_URL ||
    process.env.NEXT_PUBLIC_GATEWAY_BASE ||
    '';

  const token =
    process.env.MAGENTO_ADMIN_TOKEN ||
    process.env.M2_ADMIN_TOKEN ||
    process.env.M2_TOKEN ||
    '';

  return NextResponse.json({
    hasBase: Boolean(rawBase),
    hasToken: Boolean(token),
    base: rawBase || null,
    tokenPrefix: token ? token.slice(0, 8) + '…' : null,
  });
}
TS
echo "  ✔ app/api/_debug/env/route.ts"

# --- Rydd cache ---
echo "→ Rydder .next-cache"
rm -rf .next 2>/dev/null || true
rm -rf .next-cache 2>/dev/null || true

echo "✓ Ferdig!"
echo "Start dev på nytt: npm run dev"
echo "Test: curl -s http://localhost:3000/api/_debug/env | jq"