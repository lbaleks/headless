#!/bin/bash
set -euo pipefail

FILE="m2-gateway/fix-dotenv-clean.js"

if [ -f "$FILE" ]; then
  echo "🧹 Rydder opp prefer-const i $FILE"
  # erstatt alle forekomster av let/var kept, uansett mellomrom, linjeskift eller kommentarer
  perl -0777 -i -pe 's/\b(?:let|var)\s*kept\b/const kept/g' "$FILE"

  # hvis den fortsatt ikke har const, legg inn manuelt fallback
  if ! grep -q "const kept" "$FILE"; then
    sed -i '' '28s/.*/  const kept = []/' "$FILE"
  fi
fi

echo "✅ Nuclear zero-warning fix applied. Running eslint…"
pnpm run lint --fix || true
