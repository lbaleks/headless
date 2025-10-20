#!/usr/bin/env bash
set -euo pipefail

FP="app/admin/products/[id]/page.tsx"

echo "==> Fikser funksjonssignatur i $FP"
if [[ -f "$FP" ]]; then
  cp "$FP" "$FP.bak.$(date +%s)"
  # Bytt hele linja med riktig signatur
  # (robust: matcher linja som starter med 'export default function ProductDetail(')
  perl -0777 -pe "s|export default function ProductDetail\\([\\s\\S]*?\\)\\s*\\{|\nexport default function ProductDetail({ params }: { params: Promise<{ id: string }> }) {\n|e if $. == 0" "$FP" > "$FP.tmp"
  mv "$FP.tmp" "$FP"
else
  echo "⚠️ Fant ikke $FP"
fi

echo "==> Rydder webpack-cache (fikser ENOENT-støy)"
rm -rf .next/cache/webpack || true

echo "Ferdig. Start dev-server på nytt om nødvendig."