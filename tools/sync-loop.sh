#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://localhost:3000}"
while true; do
  echo "→ run-sync @ $(date)"
  curl -sf -X POST "$BASE/api/jobs/run-sync" >/dev/null || true
  sleep 300
done
