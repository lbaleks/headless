#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://localhost:3000}"

echo "→ Installerer /api/debug/health …"
mkdir -p app/api/debug/health
cat > app/api/debug/health/route.ts <<'TS'
// app/api/debug/health/route.ts
import { NextResponse } from 'next/server'
export const dynamic = 'force-dynamic'
export const revalidate = 0
export async function GET() {
  return NextResponse.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } })
}
TS

echo "→ Verifiserer health…"
resp="$(curl -s "$BASE/api/debug/health" || true)"
ok="$(printf '%s' "$resp" | jq -r '.ok' 2>/dev/null || true)"
if [ "$ok" = "true" ]; then
  echo "   ✓ Health OK"
else
  echo "   ⚠ Health svarte ikke {ok:true}. Rått svar:"
  echo "$resp"
fi
SH
chmod +x tools/autoinstall-health.sh

# 2) Koble inn i autoinstall-all (oppretter hvis mangler)
cat > tools/autoinstall-all.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://localhost:3000}"

echo "→ Sikrer runtime-mapper"
mkdir -p var/{jobs,audit,locks}

echo "→ Health route"
tools/autoinstall-health.sh

echo "→ Verifiser dev-server og kjør røyk-test"
# Enkel røyk-test: health + run-sync + latest
curl -s "$BASE/api/debug/health" | jq '.ok' || true
RUN=$(curl -s -X POST "$BASE/api/jobs/run-sync" | jq -r '.id // empty')
LATEST=$(curl -s "$BASE/api/jobs/latest" | jq -r '.item.id // empty' 2>/dev/null || true)
echo "   last run:   $RUN"
echo "   last latest:$LATEST"
echo "✓ Ferdig"
SH
chmod +x tools/autoinstall-all.sh

# 3) Legg til npm-scripts (idempotent)
tmp=$(mktemp)
jq '
  .scripts = (.scripts // {}) |
  .scripts.autoinstall = (.scripts.autoinstall // "bash tools/autoinstall-all.sh") |
  .scripts["verify:devops"] = (.scripts["verify:devops"] // "bash tools/autoinstall-verify.sh")
' package.json > "$tmp" && mv "$tmp" package.json

echo "→ Klart. Du kan nå kjøre:"
echo "   npm run autoinstall"
echo "   npm run verify:devops"