#!/usr/bin/env bash
set -euo pipefail
f="category-sync.sh"
[ -f "$f" ] || { echo "❌ Fant ikke $f"; exit 1; }

# Legg inn en helper-funksjon VALIDATE_CATS rett etter shebang og set -euo pipefail
perl -0777 -pe '
  s/\A(\#\!.*?\n)(set -euo pipefail\s*\n)/$1$2
# --- VALIDATE_CATS: henter eksisterende kategori-IDer og filtrerer ønskelista ---
VALIDATE_CATS() {
  local want_json="$1"
  local existing
  existing=$(curl -sS -H "$AUTH_ADMIN" "$READ_BASE/categories" \
    | jq -c '"'"'[.. | objects | .id? | select(.!=null)]'"'"')
  # returner kun de som faktisk finnes
  jq -nc --argjson want "$want_json" --argjson have "$existing" \
    '"'"'[ $want[] | select( . as $id | ($have|index($id)) != null ) ]'"'"'
}
' -i "$f"

# Bytt stedet der skriptet beregner "new_ids" før det PUT/POSTer produktet,
# så vi alltid validerer mot eksisterende IDer.
perl -0777 -pe '
  s/(new_ids=\$\(jq -c --argjson a "\$curr" --argjson b "\$target" .*?\)\))/new_ids_raw=$(jq -c --argjson a "$curr" --argjson b "$target" '"'"'([a[], b[]] | unique | map(tonumber) | unique)'"'"')\nnew_ids=$(VALIDATE_CATS "$new_ids_raw")\nif [ "$(printf %s "$new_ids" | jq length)" -eq 0 ]; then echo "⚠️  \${sku}: ingen gyldige kategorier (hopper)"; continue; fi/s
' -i "$f"

# Sikre korrekt avslutning av case (noe miljø hadde "endac" før)
perl -0777 -pe 's/\bendac\b/esac/g' -i "$f"

# Fjern CR og sett kjørbar
perl -pi -e 's/\r$//' "$f"
chmod +x "$f"

echo "✅ $f oppdatert (validerer kategori-IDer automatisk)."
