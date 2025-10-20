#!/bin/bash
set -euo pipefail
FILE="app/admin/products/page.tsx"
[ -f "$FILE" ] || { echo "Finner ikke $FILE"; exit 1; }

# 1) Fjern ev. eksport-linjer for revalidate/dynamic
perl -0777 -pe "s/^\s*export\s+const\s+revalidate\s*=\s*0\s*;?\s*\n//mg" -i "$FILE"
perl -0777 -pe "s/^\s*export\s+const\s+dynamic\s*=\s*['\"][^'\"]+['\"]\s*;?\s*\n//mg" -i "$FILE"

# 2) Sørg for at "use client" finnes og er på linje 1
if ! grep -q '^"use client";' "$FILE"; then
  tmp=$(mktemp)
  printf '"use client";\n' > "$tmp"
  cat "$FILE" >> "$tmp"
  mv "$tmp" "$FILE"
else
  # flytt den til topp om nødvendig
  if ! head -n 1 "$FILE" | grep -q '^"use client";'; then
    sed -n '1,/^"use client";/p' "$FILE" >/dev/null
    # fjern eksisterende linje og prepend øverst
    perl -0777 -pe 's/^"use client";\s*\n//m' -i "$FILE"
    tmp=$(mktemp)
    printf '"use client";\n' > "$tmp"
    cat "$FILE" >> "$tmp"
    mv "$tmp" "$FILE"
  fi
fi

echo "✅ page.tsx OK: \"use client\" øverst, ingen revalidate/dynamic-eksporter i client-fil."

# 3) Ren rebuild-cache for sikkerhets skyld
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true
echo "🧹 Ryddet build-caches. Start på nytt: pnpm dev"
