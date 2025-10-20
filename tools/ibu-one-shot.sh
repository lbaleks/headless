#!/usr/bin/env bash
set -euo pipefail
tools/ibu-assert-env.sh
echo "🚀 Kjør IBU E2E (admin JWT)…"
tools/ibu-smoketest.sh "${1:-TEST-RED}" "${2:-37}"
echo "🎉 Smoke OK"
