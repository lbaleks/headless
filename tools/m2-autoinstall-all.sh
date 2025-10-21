#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log() { printf "%s\n" "$*"; }

# 0) Sikker .gitignore-oppdatering (ingen bash history expansion her inne uansett)
if ! grep -qE '^\Q.env*\E$' .gitignore 2>/dev/null; then
  printf "\n.env*\n!.env.example\n" >> .gitignore || true
  log "📄 Oppdatert .gitignore for .env-filer"
fi

# 1) Sørg for at hjelpe-skript finnes (lag dem hvis mangler)
if [ ! -x tools/next15-fix-runtime2.sh ]; then
  cat > tools/next15-fix-runtime2.sh <<'PATCH'
#!/usr/bin/env bash
set -euo pipefail
find app/api -type f \( -name 'route.ts' -o -name 'route.js' \) | while IFS= read -r f; do
  perl -0777 -pe "s/export\\s+const\\s+runtime\\s*=\\s*[\\s\\S]*?;\\s*\\n?//g" "$f" > "$f.__clean__"
  printf "export const runtime = 'nodejs';\n" > "$f.__hdr__"
  cat "$f.__hdr__" "$f.__clean__" > "$f.__new__"
  mv "$f.__new__" "$f"
  rm -f "$f.__hdr__" "$f.__clean__"
  echo "✔ normalized runtime in $f"
done
echo "— Scan:"
grep -Rn "export const runtime" app/api | wc -l | xargs -I{} echo "{} filer har runtime-linjen"
PATCH
  chmod +x tools/next15-fix-runtime2.sh
fi

if [ ! -x tools/fix-pricing-stubs.sh ]; then
  cat > tools/fix-pricing-stubs.sh <<'PATCH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p data
cat > data/pricing.ts <<'TS'
// data/pricing.ts — temporary stubs used by API routes
export type QuoteLine = { sku: string; qty: number; price?: number }
export function quoteLine(input: QuoteLine): QuoteLine { return input }
export const pricingDB = {
  rules: [] as Array<{ id: string; name: string; match?: unknown; action?: unknown }>,
  lists: [] as Array<{ id: string; name: string; items?: unknown[] }>,
}
// console.log("pricing.ts stub loaded");
TS
echo "✅ data/pricing.ts skrevet"
PATCH
  chmod +x tools/fix-pricing-stubs.sh
fi

# 2) Hent/skriv Magento-token + env (bruker ditt eksisterende wireup-skript om det finnes)
if [ -x tools/m2-wireup.sh ]; then
  log "🔐 Kjører tools/m2-wireup.sh (henter token + skriver env) ..."
  bash tools/m2-wireup.sh
else
  log "⚠️  Fant ikke tools/m2-wireup.sh — hopper over env-wireup (forvent at .env.local allerede har token)."
fi

# 3) Next15 runtime normalisering
log "🛠  Normaliserer runtime= 'nodejs' i App Router API-routes ..."
bash tools/next15-fix-runtime2.sh

# 4) Pricing-stubber for å tilfredsstille imports
log "🧩 Installerer pricing-stubber ..."
bash tools/fix-pricing-stubs.sh

# 5) Kill ev. gammel server
log "🧹 Stopper ev. Next på :3000 ..."
lsof -tiTCP:3000 -sTCP:LISTEN | xargs kill -9 2>/dev/null || true

# 6) Clean og build
log "🧼 Renser Next-cache ..."
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true

log "🔧 Bruker Volta/Node (hvis installert) ..."
export PATH="$HOME/.volta/bin:$PATH"; hash -r || true
node -v || true
pnpm -v || true

log "🏗️  Kjører build ..."
volta run pnpm run build || pnpm run build

# 7) Start prod-server m/logg
log "🚀 Starter prod-server på :3000"
(set -a; . ./.env.local 2>/dev/null || true; set +a; \
  (volta run pnpm start -p 3000 || pnpm start -p 3000) \
  > /tmp/next.out 2>&1 & echo $! > /tmp/next.pid)

sleep 1

# 8) Verifisering
log "🔎 Verifiserer env-endepunkt"
/usr/bin/env bash -lc 'curl -s http://localhost:3000/api/debug/env/magento || true'

log "🔎 Verifiserer Magento-helse"
/usr/bin/env bash -lc 'curl -s http://localhost:3000/api/magento/health || true'

log "ℹ️  Serverlogger: tail -n 200 /tmp/next.out"
