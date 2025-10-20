#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

log "Installerer JobsFooter (poll /api/jobs/latest)"

cat > src/components/JobsFooter.tsx <<'TSX'
"use client"
import useSWR from "swr"
const fetcher = (url:string)=>fetch(url).then(r=>r.json())

export default function JobsFooter() {
  const { data } = useSWR("/api/jobs/latest", fetcher, { refreshInterval: 10000 })
  const job = data?.item
  return (
    <div className="text-xs text-gray-500 mt-8 border-t pt-2">
      {job
        ? <>Last job: <b>{job.id}</b> ({job.counts?.products ?? 0} products)</>
        : "No job info yet"}
    </div>
  )
}
TSX

# injiser i admin/layout.tsx
grep -q JobsFooter app/admin/layout.tsx || \
  sed -i '' '/<\/main>/i\
      import JobsFooter from "@/src/components/JobsFooter";\
      <JobsFooter />\
  ' app/admin/layout.tsx || true

log "Ferdig ✅  Åpne admin-dashboard for footer med siste sync"
