#!/bin/bash
set -euo pipefail

F="app/admin/products/page.tsx"
[ -f "$F" ] || { echo "❌ Finner ikke $F"; exit 1; }

echo "🔧 (v3) Rydder imports og cleanup i $F"

TMPDIR="$(mktemp -d)"
IM="$TMPDIR/imports.txt"
BODY="$TMPDIR/body.tsx"
STAGE1="$TMPDIR/stage1.tsx"
OUT="$TMPDIR/out.tsx"

# 1) Plukk ut imports og dedupliser
grep -E '^[[:space:]]*import[[:space:]].*' "$F" || true > "$IM"
# Dedupliser med awk, behold rekkefølge
awk '!seen[$0]++' "$IM" > "$IM.dedup" && mv "$IM.dedup" "$IM"

# 2) Fjern import-linjer fra body
sed -E '/^[[:space:]]*import[[:space:]]/d' "$F" > "$BODY"

# 3) Hvis <Link ...> finnes, men ingen next/link-import, legg den til
if grep -q '<Link[[:space:]>]' "$BODY"; then
  if ! grep -q "from[[:space:]]+['\"]next/link['\"]" "$IM"; then
    printf "import Link from 'next/link';\n%s" "$(cat "$IM")" > "$IM.withlink"
    mv "$IM.withlink" "$IM"
  fi
fi

# 4) Sett imports etter ev. "use client" header-blokk, ellers helt øverst.
#    Vi behandler en sammenhengende blokk med kun 'use client' linjer på toppen.
awk -v IMPORTS="$(printf "%s" "$(cat "$IM")" | sed 's/[&/\]/\\&/g')" '
BEGIN{ inserted=0; seenNonHeader=0 }
{
  if (!seenNonHeader && $0 ~ /^[ \t]*("use client"|\x27use client\x27)[ \t]*;?[ \t]*$/) {
    # bare print headerlinjen; vi setter inn imports etter hele headerblokken under
    print $0
    next
  }
  if (!seenNonHeader) {
    # Første ikke-header-linje: sett inn imports nå
    print IMPORTS
    inserted=1
    seenNonHeader=1
  }
  print $0
}
END{
  if (!inserted) {
    # filen var helt tom eller kun header – sett imports til slutt
    print IMPORTS
  }
}
' "$BODY" > "$STAGE1"

# 5) Rydd opp useEffect cleanup som havnet rart i tidligere redigeringer
sed -E \
  -e 's@return[[:space:]]*\(\)[[:space:]]*=>[[:space:]]*\{[[:space:]]*mounted[[:space:]]*=[[:space:]]*false;?[[:space:]]*clearTimeout\([[:space:]]*watchdog[[:space:]]*\)[[:space:]]*\}[[:space:]]*;?@return () => { mounted = false; clearTimeout(watchdog); }@g' \
  -e 's@return[[:space:]]*\(\)[[:space:]]*=>[[:space:]]*\{[[:space:]]*mounted[[:space:]]*=[[:space:]]*false[[:space:]]*;[[:space:]]*\}[[:space:]]*;?@return () => { mounted = false; clearTimeout(watchdog); }@g' \
  "$STAGE1" > "$OUT"

# 6) Skriv tilbake
mv "$OUT" "$F"
rm -rf "$TMPDIR"

echo "✅ Ferdig. Du kan starte dev nå (eller jeg kan restarte kjapt):"
echo "   pnpm dev"