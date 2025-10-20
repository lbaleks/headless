#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.."; pwd)"
API_DIR="$ROOT/app/api"
JOBS_DIR="$ROOT/var/jobs"
BASE="${BASE:-http://localhost:3000}"

echo "→ Sikrer mapper…"
mkdir -p "$API_DIR/jobs/run-sync" "$API_DIR/jobs/latest" "$API_DIR/_debug/health"
mkdir -p "$JOBS_DIR"

###############################################################################
# /api/jobs/run-sync (POST)
###############################################################################
RUN_SYNC_PATH="$API_DIR/jobs/run-sync/route.ts"
echo "→ Skriver $RUN_SYNC_PATH"
cat > "$RUN_SYNC_PATH" <<'TS'
// app/api/jobs/run-sync/route.ts
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

export const dynamic = 'force-dynamic'
export const revalidate = 0

async function countOf(u: string) {
  try {
    const r = await fetch(u, { cache: 'no-store' })
    if (!r.ok) return 0
    const j = await r.json()
    return (typeof j?.total === 'number') ? j.total : 0
  } catch {
    return 0
  }
}

export async function POST() {
  const base = process.env.NEXT_PUBLIC_BASE_URL || 'http://localhost:3000'

  // Hent ferske totals (ikke muterende)
  const [products, customers, orders] = await Promise.all([
    countOf(new URL('/api/products?page=1&size=1', base).toString()),
    countOf(new URL('/api/customers?page=1&size=1', base).toString()),
    countOf(new URL('/api/orders?page=1&size=1', base).toString()),
  ])

  const id = `JOB-${Date.now()}`
  const job = {
    id,
    ts: new Date().toISOString(),
    type: 'sync-all',
    started: new Date().toString(),
    finished: new Date().toString(),
    counts: { products, customers, orders },
  }

  const jobsDir = path.join(process.cwd(), 'var', 'jobs')
  await fs.mkdir(jobsDir, { recursive: true })

  // Skriv "latest.json"
  await fs.writeFile(
    path.join(jobsDir, 'latest.json'),
    JSON.stringify({ item: job }, null, 2),
    'utf8'
  )

  // Arkiver jobben også (valgfritt)
  await fs.writeFile(
    path.join(jobsDir, `${id}.json`),
    JSON.stringify(job, null, 2),
    'utf8'
  )

  return NextResponse.json(job, { headers: { 'Cache-Control': 'no-store' } })
}
TS

###############################################################################
# /api/jobs/latest (GET)
###############################################################################
LATEST_PATH="$API_DIR/jobs/latest/route.ts"
echo "→ Skriver $LATEST_PATH"
cat > "$LATEST_PATH" <<'TS'
// app/api/jobs/latest/route.ts
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

export const dynamic = 'force-dynamic'
export const revalidate = 0

export async function GET() {
  try {
    const p = path.join(process.cwd(), 'var', 'jobs', 'latest.json')
    const raw = await fs.readFile(p, 'utf8')
    const data = JSON.parse(raw)
    return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } })
  } catch (e:any) {
    return NextResponse.json(
      { error: true, message: String(e) },
      { status: 404, headers: { 'Cache-Control': 'no-store' } }
    )
  }
}
TS

###############################################################################
# /api/_debug/health (GET)
###############################################################################
HEALTH_PATH="$API_DIR/_debug/health/route.ts"
echo "→ Skriver $HEALTH_PATH"
cat > "$HEALTH_PATH" <<'TS'
// app/api/_debug/health/route.ts
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

export const dynamic = 'force-dynamic'
export const revalidate = 0

export async function GET() {
  const base = process.env.NEXT_PUBLIC_BASE_URL || 'http://localhost:3000'
  const fetchJson = async (p: string) => {
    try {
      const r = await fetch(new URL(p, base), { cache: 'no-store' })
      if (!r.ok) return { error: true, status: r.status }
      return await r.json()
    } catch (e:any) {
      return { error: true, message: String(e) }
    }
  }

  const results: any = {
    jobs: await fetchJson('/api/jobs'),
    audit: await fetchJson('/api/audit/products/TEST'),
    comp: await fetchJson('/api/products/completeness?page=1&size=1'),
  }

  const latestPath = path.join(process.cwd(), 'var', 'jobs', 'latest.json')
  try {
    const raw = await fs.readFile(latestPath, 'utf8')
    results.latest = JSON.parse(raw)
  } catch {
    results.latest = { missing: true }
  }

  const ok = !results.jobs?.error && !results.audit?.error && !results.comp?.error
  return NextResponse.json({ ok, results }, { headers: { 'Cache-Control': 'no-store' } })
}
TS

###############################################################################
# Valgfritt: legg til "dev:reset" (kjører Next på :3000 og rydder porter)
###############################################################################
if command -v jq >/dev/null 2>&1; then
  PKG="$ROOT/package.json"
  if [ -f "$PKG" ]; then
    echo "→ Oppdaterer package.json scripts (dev & dev:reset)…"
    TMP="$(mktemp)"
    jq '.scripts = (.scripts // {}) 
        | .scripts.dev = "next dev -p 3000"
        | .scripts["dev:reset"] = "bash -lc '\''lsof -ti :3000 :3001 | xargs -r kill; sleep 0.3; lsof -ti :3000 :3001 | xargs -r kill -9 2>/dev/null || true; next dev -p 3000'\''"' \
        "$PKG" > "$TMP" && mv "$TMP" "$PKG"
  fi
else
  echo "⚠ jq ikke funnet – hopper over package.json-scripts patch"
fi

echo "→ Ferdig. Start/refresh dev-server:"
echo "   npm run dev   # eller: npm run dev:reset"
echo
echo "Test (når dev kjører):"
cat <<'EOS'
  export BASE=http://localhost:3000
  curl -s -X POST "$BASE/api/jobs/run-sync" | jq '.id,.counts'
  curl -s "$BASE/api/jobs/latest"          | jq '.item.id,.item.counts'
  curl -s "$BASE/api/_debug/health"        | jq '.ok'
EOS