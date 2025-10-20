#!/bin/bash
set -euo pipefail
killall -9 node 2>/dev/null || true
rm -rf .next
echo "🔁 starter pnpm dev (logger til .next-dev.log)..."
pnpm dev 2>&1 | tee .next-dev.log || {
  code=$?
  echo "❌ pnpm dev feilet med exit $code – se .next-dev.log for detaljer"
  exit $code
}
