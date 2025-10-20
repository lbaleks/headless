#!/usr/bin/env bash
set -euo pipefail

### ⬇️ EDITER DISSE HVIS PATHS AVVIKER HOS DEG
GATEWAY_DIR="${GATEWAY_DIR:-$HOME/Documents/M2/m2-gateway}"
ADMIN_DIR="${ADMIN_DIR:-$HOME/Documents/M2/m2-admin}"   # Next.js app (admin UI)
GATEWAY_PORT="${GATEWAY_PORT:-3044}"
ADMIN_PORT="${ADMIN_PORT:-3000}"

### ⛳ MÅ-HA
command -v jq >/dev/null || { echo "❌ jq mangler (brew install jq)"; exit 1; }

### 📁 Finn mapper
[ -d "$GATEWAY_DIR" ] || { echo "❌ Finner ikke gateway-dir: $GATEWAY_DIR"; exit 1; }
[ -d "$ADMIN_DIR" ] || { echo "❌ Finner ikke admin-dir: $ADMIN_DIR"; exit 1; }

echo "➡️  Gateway: $GATEWAY_DIR  (port $GATEWAY_PORT)"
echo "➡️  Admin:   $ADMIN_DIR    (port $ADMIN_PORT)"

###############################################################################
# 1) Gateway .env
###############################################################################
pushd "$GATEWAY_DIR" >/dev/null

# Sørg for .env eksisterer
[ -f .env ] || touch .env

# Normaliser linjeendelser (mac/win) og fjern BOM/ZWSP
perl -pi -e 's/\r$//; s/\xEF\xBB\xBF//g; s/\xE2\x80\x8B//g' .env

# Les eksisterende nøkler trygt
get_kv() { awk -F= -v k="$1" '$1==k{ $1=""; sub(/^=/,""); print }' .env | tail -n1; }

MAGENTO_BASE="$(get_kv MAGENTO_BASE || true)"
MAGENTO_TOKEN="$(get_kv MAGENTO_TOKEN || true)"
MAGENTO_TIMEOUT_MS="$(get_kv MAGENTO_TIMEOUT_MS || true)"

# Skriv ønskede nøkler idempotent
upsert() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" .env; then
    # macOS sed -i ''
    sed -i '' -E "s|^${key}=.*|${key}=${val}|" .env
  else
    printf "%s=%s\n" "$key" "$val" >> .env
  fi
}

upsert PORT "$GATEWAY_PORT"
upsert CORS_ORIGIN "http://localhost:${ADMIN_PORT}"

# Bevar tidligere verdier hvis de fantes, ellers la dem stå tomme (du kan fylle inn senere)
[ -n "${MAGENTO_BASE:-}" ]         && upsert MAGENTO_BASE "$MAGENTO_BASE"
[ -n "${MAGENTO_TOKEN:-}" ]        && upsert MAGENTO_TOKEN "$MAGENTO_TOKEN"
[ -n "${MAGENTO_TIMEOUT_MS:-}" ]   && upsert MAGENTO_TIMEOUT_MS "$MAGENTO_TIMEOUT_MS"

echo "✅ Gateway .env oppdatert:"
grep -E '^(PORT|CORS_ORIGIN|MAGENTO_BASE|MAGENTO_TIMEOUT_MS)=' .env || true

popd >/dev/null

###############################################################################
# 2) Admin (.env.local) + dev-port
###############################################################################
pushd "$ADMIN_DIR" >/dev/null

# .env.local for runtime i browser
[ -f .env.local ] || touch .env.local
perl -pi -e 's/\r$//; s/\xEF\xBB\xBF//g; s/\xE2\x80\x8B//g' .env.local

if grep -qE '^NEXT_PUBLIC_GATEWAY_BASE=' .env.local; then
  sed -i '' -E "s|^NEXT_PUBLIC_GATEWAY_BASE=.*|NEXT_PUBLIC_GATEWAY_BASE=http://localhost:${GATEWAY_PORT}|" .env.local
else
  printf "NEXT_PUBLIC_GATEWAY_BASE=http://localhost:%s\n" "$GATEWAY_PORT" >> .env.local
fi

echo "✅ Admin .env.local oppdatert:"
grep -E '^NEXT_PUBLIC_GATEWAY_BASE=' .env.local || true

# Sikre at dev-script binder til riktig port (legg -p 3000 dersom ikke allerede)
if [ -f package.json ]; then
  if ! grep -q '"dev".*next dev' package.json; then
    echo "ℹ️  Fant ikke \"dev\"-script i package.json. Hopper patch."
  else
    # Legg til -p ${ADMIN_PORT} hvis ikke finnes
    if ! grep -qE "next dev.*-p[[:space:]]*${ADMIN_PORT}" package.json; then
      # legg til -p <port> på dev-linja
      node -e '
const fs=require("fs");
const pj=JSON.parse(fs.readFileSync("package.json","utf8"));
if(pj.scripts && pj.scripts.dev){
  if(!pj.scripts.dev.includes("-p ")) pj.scripts.dev += " -p " + process.env.ADMIN_PORT;
  fs.writeFileSync("package.json", JSON.stringify(pj,null,2));
  console.log("✅ Oppdatert package.json dev-script ->", pj.scripts.dev);
} else {
  console.log("ℹ️  Ingen dev-script – hopper patch.");
}
' || true
    fi
  fi
fi

popd >/dev/null

###############################################################################
# 3) Kill porter og start prosesser
###############################################################################
kill_port() {
  local port="$1"
  local pids
  pids=$(lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "💥 Stopper prosess(er) på port $port: $pids"
    kill -9 $pids || true
  fi
}

kill_port "$GATEWAY_PORT"
kill_port "$ADMIN_PORT"

# Start gateway
pushd "$GATEWAY_DIR" >/dev/null
echo "🚀 Starter gateway (port $GATEWAY_PORT)…"
# bakgrunnsstart med logg
nohup node server.js >/tmp/m2-gateway.out 2>/tmp/m2-gateway.err &
sleep 1
popd >/dev/null

# Start admin
pushd "$ADMIN_DIR" >/dev/null
echo "🚀 Starter admin (Next.js port $ADMIN_PORT)…"
if [ -f package-lock.json ] || [ -d node_modules ]; then
  nohup npm run dev -- -p "$ADMIN_PORT" >/tmp/m2-admin.out 2>/tmp/m2-admin.err &
else
  echo "ℹ️  Kjører npm install først…"
  npm install
  nohup npm run dev -- -p "$ADMIN_PORT" >/tmp/m2-admin.out 2>/tmp/m2-admin.err &
fi
sleep 2
popd >/dev/null

###############################################################################
# 4) Sanity checks
###############################################################################
echo "🧪 Sanity:"
set +e
curl -sS "http://localhost:${GATEWAY_PORT}/health/magento" | jq . || true
curl -sS "http://localhost:${GATEWAY_PORT}/ops/stats/summary" | jq . || true
echo "➡️  Åpne admin: http://localhost:${ADMIN_PORT}"
echo "➡️  (Admin henter data fra gateway på http://localhost:${GATEWAY_PORT})"

echo "✅ Ferdig."