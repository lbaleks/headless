#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# 1) Finn detaljside (typisk app/admin/products/[sku]/page.tsx)
PAGE_FILE="$(find app/admin/products -type f -path '*/page.tsx' | grep '/\[' | head -n1 || true)"
if [[ -z "${PAGE_FILE:-}" ]]; then
  log "❌ Fant ikke detaljside (app/admin/products/[...]/page.tsx)"; exit 1
fi
log "→ Fant detaljside: $PAGE_FILE"

# 2) Legg til import om mangler
if ! grep -q 'AttributeEditor' "$PAGE_FILE"; then
  tmp="$(mktemp)"
  awk '
    NR==1{
      print "import AttributeEditor from \"@/src/components/AttributeEditor\";"
    }
    { print }
  ' "$PAGE_FILE" > "$tmp" && mv "$tmp" "$PAGE_FILE"
  log "✓ Import lagt til"
else
  log "• Import allerede tilstede (ok)"
fi

# 3) Sett inn <AttributeEditor .../> før </main> om mangler
if ! grep -q '<AttributeEditor ' "$PAGE_FILE"; then
  tmp="$(mktemp)"
  awk '
    /<\/main>/ && !done {
      print "      <AttributeEditor sku={sku} initial={item?.attributes} />"
      done=1
    }
    { print }
  ' "$PAGE_FILE" > "$tmp" && mv "$tmp" "$PAGE_FILE"
  log "✓ Komponent injisert"
else
  log "• Komponent allerede injisert (ok)"
fi

log "Ferdig ✅  Åpne: /admin/products/TEST"
