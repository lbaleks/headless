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
