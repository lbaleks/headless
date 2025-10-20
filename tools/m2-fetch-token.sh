#!/usr/bin/env bash
set -euo pipefail

# --- 0) Finn og last .env.local ---
ENV_FILE=".env.local"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "✗ $ENV_FILE mangler. Opprett filen med:"
  echo "  MAGENTO_BASE_URL=https://<din-magento>/rest"
  echo "  MAGENTO_ADMIN_USERNAME=<admin-bruker>"
  echo "  MAGENTO_ADMIN_PASSWORD=<admin-passord>"
  exit 1
fi
set -a; source "$ENV_FILE"; set +a

# --- 1) Valider påkrevde variabler ---
MAGENTO_BASE_URL="${MAGENTO_BASE_URL:-}"
MAGENTO_ADMIN_USERNAME="${MAGENTO_ADMIN_USERNAME:-}"
MAGENTO_ADMIN_PASSWORD="${MAGENTO_ADMIN_PASSWORD:-}"

if [[ -z "$MAGENTO_BASE_URL" ]]; then
  echo "✗ MAGENTO_BASE_URL mangler i $ENV_FILE"; exit 1
fi
if [[ -z "$MAGENTO_ADMIN_USERNAME" || -z "$MAGENTO_ADMIN_PASSWORD" ]]; then
  echo "✗ MAGENTO_ADMIN_USERNAME/MAGENTO_ADMIN_PASSWORD mangler i $ENV_FILE"; exit 1
fi

# Sørg for at base peker på /rest
if [[ "$MAGENTO_BASE_URL" != */rest ]]; then
  MAGENTO_BASE_URL="${MAGENTO_BASE_URL%/}/rest"
fi

# --- 2) Hent admin-token via jq (tåler spesialtegn som ! i passord) ---
echo "→ Henter Magento admin token fra $MAGENTO_BASE_URL …"
RAW=$(jq -n \
  --arg u "$MAGENTO_ADMIN_USERNAME" \
  --arg p "$MAGENTO_ADMIN_PASSWORD" \
  '{username:$u, password:$p}' \
  | curl -sS -X POST -H "Content-Type: application/json" \
    -d @- "$MAGENTO_BASE_URL/V1/integration/admin/token" || true)

# Magento svarer typisk med en ren JSON-streng: "eyJ...". Trekk ut string.
TOKEN="$(printf '%s' "$RAW" | jq -r 'select(type=="string") // .token // empty' 2>/dev/null || true)"

if [[ -z "$TOKEN" ]]; then
  echo "✗ Klarte ikke å hente token. Rå respons fra Magento:"
  echo "$RAW"
  echo "Tips:"
  echo "  • Sjekk brukernavn/passord"
  echo "  • Sjekk at MAGENTO_BASE_URL peker til riktig /rest"
  exit 1
fi

# --- 3) Skriv/oppdater MAGENTO_ADMIN_TOKEN i .env.local (macOS sed -i "") ---
if grep -q '^MAGENTO_ADMIN_TOKEN=' "$ENV_FILE" 2>/dev/null; then
  sed -i "" -E "s|^MAGENTO_ADMIN_TOKEN=.*|MAGENTO_ADMIN_TOKEN=$TOKEN|" "$ENV_FILE"
else
  printf "\nMAGENTO_ADMIN_TOKEN=%s\n" "$TOKEN" >> "$ENV_FILE"
fi
echo "→ Lagret token i $ENV_FILE (prefix: ${TOKEN:0:12}…)"

# --- 4) Rydd Next-cache ---
echo "→ Rydder .next/.next-cache …"
rm -rf .next .next-cache 2>/dev/null || true

echo "✓ Ferdig. Start dev på nytt: npm run dev"
echo "  Verifiser: curl -s http://localhost:3000/api/_debug/ping | jq ."
