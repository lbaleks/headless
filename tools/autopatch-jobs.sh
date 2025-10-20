# tools/autopatch-jobs.sh
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
JOBS_DIR="$ROOT/var/jobs"
RUN_SYNC="$ROOT/app/api/jobs/run-sync/route.ts"
LATEST_DIR="$ROOT/app/api/jobs/latest"
LATEST_ROUTE="$LATEST_DIR/route.ts"
HEALTH_DIR="$ROOT/app/api/_debug/health"
HEALTH_ROUTE="$HEALTH_DIR/route.ts"
PKG="$ROOT/package.json"

echo "→ Sikrer mapper"
mkdir -p "$JOBS_DIR" "$LATEST_DIR" "$HEALTH_DIR" "$ROOT/app/api/jobs/run-sync"

echo "→ Patcher /api/jobs/run-sync til å oppdatere latest.json"

if [[ -f "$RUN_SYNC" ]]; then
  cp "$RUN_SYNC" "$RUN_SYNC.bak"
  # Injiser blokk før første 'return NextResponse.json(job'
  awk '
    BEGIN{ injected=0 }
    /return[[:space:]]+NextResponse\.json\(job\)/ && injected==0 {
      print "  const JOBS_DIR = path.join(process.cwd(), '\''var'\'', '\''jobs'\'');"
      print "  await fs.mkdir(JOBS_DIR, { recursive: true });"
      print "  await fs.writeFile(path.join(JOBS_DIR, '\''latest.json'\''), JSON.stringify({ item: job }, null, 2), '\''utf8'');"
      injected=1
    }
    { print }
  ' "$RUN_SYNC.bak" > "$RUN_SYNC.tmp"

  # Sørg for imports (fs & path)
  if ! grep -q "from 'fs'" "$RUN_SYNC.tmp"; then
    sed -i '' "1s|^|import { promises as fs } from 'fs'\n|" "$RUN_SYNC.tmp" 2>/dev/null || true
  fi
  if ! grep -q "from 'path'" "$RUN_SYNC.tmp"; then
    sed -i '' "1s|^|import path from 'path'\n|" "$RUN_SYNC.tmp" 2>/dev/null || true
  fi

  mv "$RUN_SYNC.tmp" "$RUN_SYNC"
else
  echo "  ⚠ Fant ikke $RUN_SYNC – oppretter minimal handler med latest-skriving"
  cat > "$RUN_SYNC" <<'TS'
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

async function doSync(){
  // ← her kaller du eksisterende sync-funksjoner for products/customers/orders
  return { products: 8, customers: 1, orders: 6 } // placeholder
}

export async function POST(){
  const id = `JOB-${Date.now()}`
  const counts = await doSync()
  const job = {
    id, ts: new Date().toISOString(), type: 'sync-all',
    started: new Date().toString(), finished: new Date().toString(), counts
  }

  const JOBS_DIR = path.join(process.cwd(), 'var', 'jobs')
  await fs.mkdir(JOBS_DIR, { recursive: true })
  await fs.writeFile(path.join(JOBS_DIR, `${id}.json`), JSON.stringify(job, null, 2), 'utf8')
  await fs.writeFile(path.join(JOBS_DIR, 'latest.json'), JSON.stringify({ item: job }, null, 2), 'utf8')

  return NextResponse.json(job)
}
TS
fi

echo "→ Skriver /api/jobs/latest (fallback til nyeste JOB-*.json)"
cat > "$LATEST_ROUTE" <<'TS'
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export async function GET() {
  const JOBS_DIR = path.join(process.cwd(), 'var', 'jobs')
  const latestPath = path.join(JOBS_DIR, 'latest.json')

  try {
    const txt = await fs.readFile(latestPath, 'utf8')
    const j = JSON.parse(txt)
    if (j?.item?.id) return NextResponse.json(j)
  } catch { /* fallback below */ }

  try {
    const entries = await fs.readdir(JOBS_DIR)
    const files = entries.filter(f => f.startsWith('JOB-') && f.endsWith('.json'))
    if (files.length === 0) return NextResponse.json({ item: null })
    files.sort().reverse()
    const txt = await fs.readFile(path.join(JOBS_DIR, files[0]), 'utf8')
    const item = JSON.parse(txt)
    return NextResponse.json({ item })
  } catch {
    return NextResponse.json({ item: null })
  }
}
TS

echo "→ Skriver /api/_debug/health"
cat > "$HEALTH_ROUTE" <<'TS'
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export async function GET() {
  const base = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || null
  const token = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || null
  const latestPath = path.join(process.cwd(), 'var', 'jobs', 'latest.json')
  let latestOk = false
  try { await fs.access(latestPath); latestOk = true } catch {}

  return NextResponse.json({
    ok: true,
    env: { base: !!base, token: !!token },
    files: { latestJson: latestOk }
  })
}
TS

echo "→ (Valgfritt) Legger til npm scripts"
if command -v jq >/dev/null 2>&1; then
  TMP="$(mktemp)"
  jq '
    .scripts = (.scripts // {}) |
    .scripts["autopatch:jobs"] = (.scripts["autopatch:jobs"] // "bash tools/autopatch-jobs.sh") |
    .scripts["verify:jobs"]    = (.scripts["verify:jobs"] // "bash -lc '\''set -e; export BASE=http://localhost:3000; curl -s -X POST \"$BASE/api/jobs/run-sync\" | jq -c . > /dev/null; curl -s \"$BASE/api/jobs/latest\" | jq -c . > /dev/null; echo OK'\''")
  ' "$PKG" > "$TMP" && mv "$TMP" "$PKG"
else
  echo "  ⚠ jq ikke funnet – hopper over package.json-oppdatering"
fi

echo "→ Røyk-test"
BASE="${BASE:-http://localhost:3000}"
set +e
ID_AND_COUNTS="$(curl -s -X POST "$BASE/api/jobs/run-sync" | jq -c '{id,counts}')"
LATEST="$(curl -s "$BASE/api/jobs/latest" | jq -c '{id:(.item.id), counts:(.item.counts)}')"
HEALTH="$(curl -s "$BASE/api/_debug/health" | jq -c '.')"
set -e

echo "  run-sync:   $ID_AND_COUNTS"
echo "  latest:     $LATEST"
echo "  health:     $HEALTH"
echo "✓ Ferdig. Restart dev-server om ikke hot-reload plukker opp: npm run dev"