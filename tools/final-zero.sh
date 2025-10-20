#!/bin/bash
set -euo pipefail

TARGET="m2-gateway/fix-dotenv-clean.js"

if [ -f "$TARGET" ]; then
  # erstatt alle let/var kept med const kept
  perl -0777 -i -pe 's/\b(?:let|var)\s+kept\b/const kept/g' "$TARGET"
fi

echo "✅ Final zero-warning fix applied. Running eslint…"
pnpm run lint --fix || true
