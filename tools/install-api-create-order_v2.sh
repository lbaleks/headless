#!/usr/bin/env bash
set -euo pipefail

root_dir="$(pwd)"
file="$root_dir/app/admin/orders/new/OrderCreate.client.tsx"

say(){ printf "%s\n" "$*"; }

if [ ! -f "$file" ]; then
  say "⚠️ Fant ikke $file"
  exit 1
fi

say "→ Backup av filen"
cp "$file" "$file.bak"

say "→ Sikrer korrekt import (fjerner duplikater først)"
# Fjern eksisterende importlinjer som importerer apiCreateOrder
tmp="$(mktemp)"
awk '!($0 ~ /^import / && $0 ~ /apiCreateOrder/)' "$file" > "$tmp" && mv "$tmp" "$file"

# Legg inn korrekt import hvis den ikke finnes fra før
if ! grep -q "from '@/src/lib/orders'" "$file"; then
  first_import_line="$(grep -n '^import ' "$file" | head -n1 | cut -d: -f1 || true)"
  tmp="$(mktemp)"
  if [ -n "$first_import_line" ]; then
    awk -v L="$first_import_line" 'NR==L{print; print "import { apiCreateOrder } from '\''@/src/lib/orders'\''"; next}1' "$file" > "$tmp"
  else
    { echo "import { apiCreateOrder } from '@/src/lib/orders'"; cat "$file"; } > "$tmp"
  fi
  mv "$tmp" "$file"
else
  # Sørg for at selve named exporten står riktig dersom den allerede finnes
  if ! grep -q "^import \{ .*apiCreateOrder.* \} from '@/src/lib/orders'" "$file"; then
    # Sett inn (en) tydelig import-linje på toppen hvis vi fant en annen var. av importen
    tmp="$(mktemp)"
    { echo "import { apiCreateOrder } from '@/src/lib/orders'"; cat "$file"; } > "$tmp"
    mv "$tmp" "$file"
  fi
fi

say "→ Gir lokalt kolliderende funksjonsnavn nytt navn (…Local)"
# macOS-vennlige perl-one-liners for å rename lokal funksjon/const
# (unngår å berøre imports)
perl -i -pe 's/\bexport\s+async\s+function\s+apiCreateOrder\b/export async function apiCreateOrderLocal/g' "$file"
perl -i -pe 's/\basync\s+function\s+apiCreateOrder\b/async function apiCreateOrderLocal/g' "$file"
perl -i -pe 's/\bconst\s+apiCreateOrder\s*=\s*async/const apiCreateOrderLocal = async/g' "$file"
perl -i -pe 's/\bfunction\s+apiCreateOrder\s*\(/function apiCreateOrderLocal(/g' "$file"

say "→ Rydder .next-cache"
rm -rf "$root_dir/.next" "$root_dir/.next-cache" 2>/dev/null || true

say "✓ Ferdig. Start dev-server på nytt (npm run dev)."