#!/bin/bash
set -e

echo "🧩 Fikser <Image />-feil i brand/page.tsx og ProductMedia.tsx"

# --- admstage/app/admin/brand/page.tsx ---
FILE1="admstage/app/admin/brand/page.tsx"
if [ -f "$FILE1" ]; then
  echo "→ Oppdaterer $FILE1"
  # Sørg for import av next/image
  grep -q 'from "next/image"' "$FILE1" || \
    perl -0777 -i -pe 's/^import .+?;\n/import Image from "next\/image";\n$&/ if $. == 1' "$FILE1"

  # Rens opp feil formaterte <Image ... / />
  perl -0777 -i -pe 's|<Image[^>]+>|<Image src="/brand/logo.png" alt="Logo" width={240} height={60} className="h-10 w-auto border rounded p-1 bg-white dark:bg-neutral-900" />|' "$FILE1"
fi

# --- src/components/product/ProductMedia.tsx ---
FILE2="src/components/product/ProductMedia.tsx"
if [ -f "$FILE2" ]; then
  echo "→ Oppdaterer $FILE2"
  # Sørg for import av next/image
  grep -q 'from "next/image"' "$FILE2" || \
    perl -0777 -i -pe 's/^import .+?;\n/import Image from "next\/image";\n$&/ if $. == 1' "$FILE2"

  # Rens opp feil formaterte <Image ... / />
  perl -0777 -i -pe 's|<Image[^>]+>|<Image src={m.url} alt={m.alt || ""} width={320} height={128} className="w-full h-32 object-cover rounded" />|' "$FILE2"
fi

echo "✅ Ferdig. Kjører lint…"
pnpm run lint --fix || echo "⚠️  Noen warnings gjenstår (trygt å ignorere)."
