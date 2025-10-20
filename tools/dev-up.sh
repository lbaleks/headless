#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}
lsof -ti :3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
rm -rf .next
npm run dev --silent >/tmp/next-dev.log 2>&1 &
pid=$!
echo "→ Starter dev (pid=$pid), venter på readiness…"
deadline=$((SECONDS+30)); ok=0
while [ $SECONDS -lt $deadline ]; do
  if curl -fsS "$BASE/api/debug/health" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
if [ $ok -eq 1 ]; then
  echo "✓ Dev oppe på $BASE"
else
  echo "✗ Dev ikke verifisert. Utskrift av /tmp/next-dev.log:"
  tail -n +1 /tmp/next-dev.log | sed -n '1,200p'
fi
