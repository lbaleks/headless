#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:3000}"
SLEEP="${SLEEP:-120}"
echo "→ Dev scheduler: kjører sync hvert ${SLEEP}s mot ${BASE}"
while true; do
  curl -s -X POST "$BASE/api/jobs/run-sync" | jq -r '.id + " " + ( .counts|tostring )' || true
  sleep "$SLEEP"
done
