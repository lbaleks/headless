#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.volta/bin:$PATH"; hash -r

echo "🔐 Henter admin-token fra Magento…"
: "${MAGENTO_BASE_URL:=https://m2-dev.litebrygg.no/rest}"
: "${MAGENTO_URL:=${MAGENTO_BASE_URL}}"
: "${MAGENTO_ADMIN_USERNAME:=aleksander}"
: "${MAGENTO_ADMIN_PASSWORD:=Riise1986!}"

TOKEN="$(curl -fsS -X POST -H 'Content-Type: application/json' \
  "$MAGENTO_URL/V1/integration/admin/token" \
  -d "{\"username\":\"$MAGENTO_ADMIN_USERNAME\",\"password\":\"$MAGENTO_ADMIN_PASSWORD\"}" \
  | tr -d '"' || true)"

if [ -z "${TOKEN:-}" ]; then
  echo "❌ Fikk ikke token fra $MAGENTO_URL"; exit 1
fi
echo "✅ Token (maskert): ${TOKEN:0:3}***"

echo "🧹 Rydder duplikate linjer i .env.local og .env.production.local…"
for F in .env.local .env.production.local; do
  touch "$F"
  # Fjern gamle linjer for alle relevante nøkler
  sed -i '' -E '/^(MAGENTO(_ADMIN)?_(TOKEN|BEARER|ACCESS_TOKEN)|M2_(ADMIN_)?(TOKEN|BEARER)|MAGENTO_URL|MAGENTO_BASE_URL)=/d' "$F"
done

echo "📝 Skriver alle vanlige nøkler (flere alias) til .env.local og .env.production.local…"
for F in .env.local .env.production.local; do
  {
    echo "MAGENTO_URL=$MAGENTO_URL"
    echo "MAGENTO_BASE_URL=$MAGENTO_URL"
    echo "MAGENTO_ADMIN_TOKEN=$TOKEN"
    echo "MAGENTO_TOKEN=$TOKEN"
    echo "MAGENTO_ACCESS_TOKEN=$TOKEN"
    echo "MAGENTO_BEARER=Bearer $TOKEN"
    echo "MAGENTO_ADMIN_BEARER=Bearer $TOKEN"
    echo "M2_TOKEN=$TOKEN"
    echo "M2_ADMIN_TOKEN=$TOKEN"
    echo "M2_BEARER=Bearer $TOKEN"
  } >> "$F"
done
echo "✅ Env oppdatert"

echo "🛑 Stopper ev. prosess på :3000"
lsof -tiTCP:3000 -sTCP:LISTEN | xargs kill -9 2>/dev/null || true
pkill -f "next start" 2>/dev/null || true

echo "🧼 Renser .next-cache"
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true

echo "🏗️ Bygger (Next ser: .env.production.local, .env.local)…"
volta run pnpm run build

echo "🚀 Starter prod-server"
volta run pnpm start -p 3000 > /tmp/next.out 2>&1 & echo $! > /tmp/next.pid

echo "⏳ Sjekker env-endepunkt"
for i in {1..20}; do
  sleep 0.5
  R="$(curl -fsS http://localhost:3000/api/debug/env/magento 2>/dev/null || true)"
  if [ -n "$R" ]; then
    echo "$R"
    TOK="$(echo "$R" | sed -n 's/.*"MAGENTO_TOKEN_masked":"\([^"]*\)".*/\1/p')"
    if [ -n "$TOK" ] && [ "$TOK" != "<empty>" ]; then
      echo "✅ Token synlig i runtime"; exit 0
    fi
  fi
done

echo "⚠️  /api/debug/env/magento viser fortsatt tom token."
echo "   • Dette endepunktet kan være kodet til å vise tom streng selv om auth virker."
echo "   • Tester Magento API-helse…"
curl -fsS http://localhost:3000/api/magento/health || true
echo
echo "ℹ️  Se også /tmp/next.out for server-logger."
exit 0
