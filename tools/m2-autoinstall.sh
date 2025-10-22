: "${MAGENTO_USER:?Missing MAGENTO_USER in .env.local}"; : "${MAGENTO_PASS:?Missing MAGENTO_PASS in .env.local}"
# tools/m2-autoinstall.sh
#!/usr/bin/env bash
set -euo pipefail

# ---- config / defaults ----
MAGENTO_BASE_URL_DEFAULT="https://m2-dev.litebrygg.no/rest"
PORT="${PORT:-3000}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Inputs via env (kan også legges i .env.local i forkant)
MAGENTO_USER="${MAGENTO_USER:-${MAGENTO_ADMIN_USERNAME:-aleksander}}"
MAGENTO_PASS="${MAGENTO_PASS:-${MAGENTO_ADMIN_PASSWORD:-}}"
MAGENTO_BASE_URL="${MAGENTO_BASE_URL:-$(grep -E '^MAGENTO_(BASE_)?URL=' .env.local 2>/dev/null | tail -n1 | cut -d= -f2- || echo "$MAGENTO_BASE_URL_DEFAULT")}"

if [[ -z "${MAGENTO_PASS}" ]]; then
  echo "⚠️  MAGENTO_PASS er tom. Sett MAGENTO_PASS eller MAGENTO_ADMIN_PASSWORD i miljø/CI."
  exit 1
fi

echo "🔐 Henter admin-token fra ${MAGENTO_BASE_URL} …"
TOKEN="$(curl -sS -X POST -H 'Content-Type: application/json' \
  "${MAGENTO_BASE_URL}/V1/integration/admin/token" \
  -d "{\"username\":\"${MAGENTO_USER}\",\"password\":\"${MAGENTO_PASS}\"}" | tr -d '"')"

if [[ -z "${TOKEN}" || "${TOKEN}" == *"message"* ]]; then
  echo "❌ Klarte ikke hente token. Svar: ${TOKEN}"
  exit 1
fi
MASKED="$(printf '%s' "${TOKEN}" | awk '{print substr($0,1,3)"***"substr($0,length($0)-1)}')"
echo "✅ Token mottatt (maskert): ${MASKED}"

# ---- oppdater .env.* trygt ----
echo "🧹 Rydder duplikate linjer i .env.local og .env.production.local …"
touch .env.local .env.production.local
for f in .env.local .env.production.local; do
  # fjern gamle varianter
  sed -i '' -E '/^MAGENTO_(ADMIN_)?TOKEN=/d' "$f" 2>/dev/null || true
  sed -i '' -E '/^(MAGENTO_(BASE_)?URL|MAGENTO_URL)=/d' "$f" 2>/dev/null || true
  sed -i '' -E '/^(MAGENTO_ACCESS_TOKEN|M2_(ADMIN_)?TOKEN|MAGENTO_(ADMIN_)?BEARER|MAGENTO_BEARER|M2_BEARER)=/d' "$f" 2>/dev/null || true

  {
    printf 'MAGENTO_BASE_URL=%s\n' "$MAGENTO_BASE_URL"
    printf 'MAGENTO_URL=%s\n' "$MAGENTO_BASE_URL"
    printf 'MAGENTO_ADMIN_TOKEN=%s\n' "$TOKEN"
    printf 'MAGENTO_TOKEN=%s\n' "$TOKEN"
    # ekstra alias som enkelte moduler/patcher bruker:
    printf 'MAGENTO_ACCESS_TOKEN=%s\n' "$TOKEN"
    printf 'M2_ADMIN_TOKEN=%s\n' "$TOKEN"
    printf 'M2_TOKEN=%s\n' "$TOKEN"
    printf 'MAGENTO_ADMIN_BEARER=%s\n' "$TOKEN"
    printf 'MAGENTO_BEARER=%s\n' "$TOKEN"
    printf 'M2_BEARER=%s\n' "$TOKEN"
  } >> "$f"
done
echo "✅ Env skrevet"

# ---- .gitignore – legg til uten !-trøbbel ----
echo "📝 Oppdaterer .gitignore"
touch .gitignore
# bruk printf %s\n for å unngå history expansion og \n-problemer
add_gitignore_line () {
  local line="$1"
  if ! grep -qxF "$line" .gitignore 2>/dev/null; then
    printf '%s\n' "$line" >> .gitignore
  fi
}
add_gitignore_line ".env*"
add_gitignore_line "!.env.example"
echo "✅ .gitignore oppdatert"

# ---- normaliser runtime i app/api/**/route.* ----
echo "🛠  Normaliserer runtime='nodejs' i app/api/**/route.*"
if command -v perl >/dev/null 2>&1; then
  while IFS= read -r f; do
    tmp="${f}.__clean__"
    hdr="${f}.__hdr__"
    # fjern alle eksisterende runtime-linjer (multiline-safe)
    perl -0777 -pe "s/export\\s+const\\s+runtime\\s*=\\s*[\\s\\S]*?;\\s*\\n?//g" "$f" > "$tmp"
    printf "export const runtime = 'nodejs';\n" > "$hdr"
    cat "$hdr" "$tmp" > "${f}.new"
    mv "${f}.new" "$f"
    rm -f "$tmp" "$hdr"
  done < <(find app/api -type f \( -name 'route.ts' -o -name 'route.js' \) 2>/dev/null)
else
  echo "⚠️  perl ikke funnet; hopper over runtime-normalisering"
fi
echo "✅ Runtime satt"

# ---- stopp ev. server ----
echo "🛑 Stopper prosesser på :${PORT}"
lsof -tiTCP:${PORT} -sTCP:LISTEN | xargs kill -9 2>/dev/null || true

# ---- build + start ----
echo "🔧 Volta/Node & pnpm"
export PATH="$HOME/.volta/bin:$PATH"; hash -r
node -v || true; pnpm -v || true

echo "🧼 Renser .next-cache"
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true

echo "🏗️  Bygger (Next ser: .env.production.local, .env.local)"
pnpm run build

echo "🚀 Starter prod-server på :${PORT}"
pnpm start -p "${PORT}" > /tmp/next.out 2>&1 &
echo $! > /tmp/next.pid
sleep 1

# ---- verifisering ----
echo "🔎 Verifiserer env-endepunkt"
for i in {1..10}; do
  OUT="$(curl -s "http://localhost:${PORT}/api/debug/env/magento" || true)"
  if [[ -n "${OUT}" ]]; then echo "${OUT}"; break; fi
  sleep 0.5
done

echo "🔎 Verifiserer Magento-helse"
curl -s "http://localhost:${PORT}/api/magento/health" || true
echo
echo "ℹ️  Serverlogger: tail -n 200 /tmp/next.out"