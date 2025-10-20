#!/usr/bin/env bash
set -euo pipefail

root_dir="$(pwd)"
lib_file="$root_dir/src/lib/orders.ts"
client_file="$root_dir/app/admin/orders/new/OrderCreate.client.tsx"

say(){ printf "%s\n" "$*"; }

say "→ Oppretter mapper om nødvendig"
mkdir -p "$(dirname "$lib_file")"

say "→ Skriver $lib_file med korrekt named export"
cat > "$lib_file" <<'TS'
export type CreateOrderPayload = {
  customer: any
  lines: Array<{ productId: string; variantId?: string; qty: number; price?: number }>
  notes?: string
}

/**
 * Klientside kall til API: POST /api/orders
 * Named export: apiCreateOrder
 */
export const apiCreateOrder = async (payload: CreateOrderPayload): Promise<any> => {
  const res = await fetch('/api/orders', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    cache: 'no-store',
  })
  if (!res.ok) {
    const txt = await res.text().catch(()=>'')
    throw new Error(`HTTP ${res.status}${txt ? `: ${txt}` : ''}`)
  }
  return res.json()
}
TS

if [ ! -f "$client_file" ]; then
  say "⚠️ Fant ikke $client_file (hopper patch, men lib er oppdatert)."
else
  say "→ Patcher import i $client_file"
  # 1) Fjern alle importlinjer som refererer apiCreateOrder (unngå duplikater/feil path)
  tmp="$(mktemp)"
  awk '!($0 ~ /^import / && $0 ~ /apiCreateOrder/)' "$client_file" > "$tmp" && mv "$tmp" "$client_file"

  # 2) Sett korrekt import etter første import-linje (eller på toppen)
  first_import_line="$(grep -n '^import ' "$client_file" | head -n1 | cut -d: -f1 || true)"
  tmp="$(mktemp)"
  if [ -n "$first_import_line" ]; then
    awk -v L="$first_import_line" 'NR==L{print; print "import { apiCreateOrder } from '\''@/src/lib/orders'\''"; next}1' "$client_file" > "$tmp"
  else
    { echo "import { apiCreateOrder } from '@/src/lib/orders'"; cat "$client_file"; } > "$tmp"
  fi
  mv "$tmp" "$client_file"

  # 3) Dersom det finnes en lokal funksjon/const med samme navn, gi den nytt navn
  perl -i -pe 's/\bexport\s+async\s+function\s+apiCreateOrder\b/export async function apiCreateOrderLocal/g' "$client_file" || true
  perl -i -pe 's/\basync\s+function\s+apiCreateOrder\b/async function apiCreateOrderLocal/g' "$client_file" || true
  perl -i -pe 's/\bconst\s+apiCreateOrder\s*=\s*async/const apiCreateOrderLocal = async/g' "$client_file" || true
  perl -i -pe 's/\bfunction\s+apiCreateOrder\s*\(/function apiCreateOrderLocal(/g' "$client_file" || true
fi

say "→ Rydder .next-cache"
rm -rf "$root_dir/.next" "$root_dir/.next-cache" 2>/dev/null || true

say "✓ Ferdig. Start dev-server på nytt (npm run dev)"