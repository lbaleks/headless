#!/bin/bash
set -euo pipefail

fix_file () {
  local f="$1"
  [ -f "$f" ] || return 0

  echo "→ Fikser $f"

  # a) Sørg for import av next/image øverst hvis mangler
  if ! grep -q 'from "next/image"' "$f"; then
    # Sett inn som første linje
    sed -i '' '1s#^#import Image from "next/image";\
#' "$f"
  fi

  # b) Normaliser selv-lukkende Image-tags (fjerner dobbelt-slash)
  #    Eks: ... "/ />"  ->  ... " />
  sed -E -i '' 's#[[:space:]]*/[[:space:]]*/>#/>#g' "$f"

  # c) Sørg for korrekt "<Image ... />" (samle opp rare mellomrom)
  sed -E -i '' 's#<Image([^>]*)[[:space:]]*/>#<Image\1 />#g' "$f"

  # d) (Valgfritt) bytt class="…" -> className="…" i JSX-filer
  sed -E -i '' 's#\bclass="#className="#g' "$f"
}

fix_file "admstage/app/admin/brand/page.tsx"
fix_file "src/components/product/ProductMedia.tsx"

echo "✅ Ferdig! Kjører lint…"
pnpm run lint --fix || true
