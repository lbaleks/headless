#!/usr/bin/env bash
# Autoinstaller: jobs run-sync (med lock), /api/jobs/latest, dev-scheduler og Makefile-targets
# Idempotent. Testet mot macOS (BSD sed).
set -euo pipefail
export LC_ALL=C

root="$(pwd)"
say(){ printf "→ %s\n" "$*"; }

req_dir(){ mkdir -p "$1"; }

write_file(){ # write_file <path> <<'EOF' … EOF
  local f="$1"
  req_dir "$(dirname "$f")"
  cat > "$f"
}

ensure_line_in_file(){ # ensure_line_in_file <file> <needle> <block-to-append-if-missing>
  local f="$1" needle="$2"
  shift 2 || true
  if [ -f "$f" ] && grep -Fq "$needle" "$f"; then
    return 0
  fi
  req_dir "$(dirname "$f")"
  { [ -f "$f" ] && cat "$f" || true; printf "\n%s\n" "$@"; } > "$f.tmp"
  mv "$f.tmp" "$f"
}

############################################
# 1) /api/jobs/run-sync (med fil-lås)
############################################
say "Installerer /api/jobs/run-sync…"
write_file "app/api/jobs/run-sync/route.ts" <<'TS'
import { NextResponse, NextRequest } from 'next/server'
import fs from 'fs/promises'
import path from 'path'
export const dynamic = 'force-dynamic'

const VAR_DIR   = path.join(process.cwd(), 'var')
const JOBS_FILE = path.join(VAR_DIR, 'jobs.json')
const LOCK_FILE = path.join(VAR_DIR, 'jobs.lock')

type Counts = { products:number; customers:number; orders:number }
type Job = { id:string; ts:string; type:'sync-all'; started:string; finished:string; counts:Counts }

async function readJobs(){
  try {
    const j = JSON.parse(await fs.readFile(JOBS_FILE,'utf8'))
    return { items: Array.isArray(j?.items)? j.items:[] }
  } catch { return { items:[] } }
}
async function writeJobs(items:Job[]){
  await fs.mkdir(VAR_DIR,{recursive:true})
  await fs.writeFile(JOBS_FILE, JSON.stringify({ total: items.length, items }, null, 2))
}
function base(req:NextRequest){
  const proto = req.headers.get('x-forwarded-proto') || (process.env.NODE_ENV==='production'?'https':'http')
  const host  = req.headers.get('host') || 'localhost:3000'
  return `${proto}://${host}`
}
async function postJSON<T=any>(url:string){
  const r = await fetch(url,{method:'POST',headers:{'content-type':'application/json'},cache:'no-store'})
  if(!r.ok) throw new Error(`POST ${url} failed: ${r.status} ${await r.text().catch(()=> '')}`)
  return await r.json().catch(()=> ({} as T))
}
async function tryLock(ttlMs=30_000){
  await fs.mkdir(VAR_DIR,{recursive:true})
  const now = Date.now()
  const raw = await fs.readFile(LOCK_FILE,'utf8').catch(()=> '')
  const old = raw ? Number(raw.trim()) : 0
  if (old && now - old < ttlMs) return false
  await fs.writeFile(LOCK_FILE, String(now))
  return true
}
async function unlock(){ await fs.rm(LOCK_FILE, { force:true }) }

export async function POST(req:NextRequest){
  if(!(await tryLock())) {
    return NextResponse.json({ ok:false, reason:'busy' }, { status: 429 })
  }
  const started = new Date()
  const b = base(req)
  let counts:Counts = { products:0, customers:0, orders:0 }
  try{
    const prod = await postJSON<{ok:boolean;saved?:number}>(`${b}/api/products/sync`).catch(()=>({ok:false,saved:0}))
    const cust = await postJSON<{ok:boolean;saved?:number}>(`${b}/api/customers/sync`).catch(()=>({ok:false,saved:0}))
    const orde = await postJSON<{ok:boolean;saved?:number}>(`${b}/api/orders/sync`).catch(()=>({ok:false,saved:0}))
    counts = { products:Number(prod.saved??0), customers:Number(cust.saved??0), orders:Number(orde.saved??0) }

    const job:Job = {
      id:`JOB-\${Date.now()}`,
      ts:new Date().toISOString(),
      type:'sync-all',
      started: started.toString(),
      finished: new Date().toString(),
      counts
    }
    const prev = await readJobs()
    await writeJobs([job, ...prev.items])
    return NextResponse.json({ id: job.id, counts })
  } finally {
    await unlock()
  }
}
TS

############################################
# 2) /api/jobs/latest
############################################
say "Installerer /api/jobs/latest…"
write_file "app/api/jobs/latest/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'
export const dynamic = 'force-dynamic'
const JOBS_FILE = path.join(process.cwd(), 'var', 'jobs.json')

export async function GET(){
  try{
    const j = JSON.parse(await fs.readFile(JOBS_FILE,'utf8'))
    const items = Array.isArray(j?.items) ? j.items : []
    return NextResponse.json({ ok:true, item: items[0] || null })
  }catch{
    return NextResponse.json({ ok:true, item: null })
  }
}
TS

############################################
# 3) Dev scheduler
############################################
say "Installerer dev-scheduler…"
write_file "tools/jobs-scheduler.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:3000}"
SLEEP="${SLEEP:-120}"
echo "→ Dev scheduler: kjører sync hvert ${SLEEP}s mot ${BASE}"
while true; do
  curl -s -X POST "$BASE/api/jobs/run-sync" | jq -r '.id + " " + ( .counts|tostring )' || true
  sleep "$SLEEP"
done
SH
chmod +x tools/jobs-scheduler.sh

############################################
# 4) Makefile targets
############################################
say "Oppdaterer Makefile-targets…"

append_targets='
run-sync:
@curl -s -X POST "http://localhost:3000/api/jobs/run-sync" | jq .

job-latest:
@curl -s "http://localhost:3000/api/jobs/latest" | jq .

job-scheduler:
SLEEP=$${SLEEP:-120} bash tools/jobs-scheduler.sh "http://localhost:3000"
'

if [ -f Makefile ]; then
  if ! grep -q 'run-sync:' Makefile 2>/dev/null; then
    printf "\n%s\n" "$append_targets" >> Makefile
  fi
else
  printf "%s\n" "$append_targets" > Makefile
fi

############################################
# 5) Avhengigheter (jq er nødvendig for visning)
############################################
if ! command -v jq >/dev/null 2>&1; then
  say "⚠ jq ikke funnet i PATH (brukes kun for pen print)."
fi

say "Ferdig ✅"
