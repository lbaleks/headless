#!/usr/bin/env bash
set -euo pipefail

FILE="app/api/orders/route.ts"
[ -f "$FILE" ] || { echo "Finner ikke $FILE"; exit 1; }

cp "$FILE" "$FILE.bak.$(date +%s)"

# 1) Kommenter ut duplikate M2_BASE / M2_TOKEN (behold første forekomst)
awk '
/^const[[:space:]]+M2_BASE[[:space:]]*=/ { if (++mb>1){print "// " $0; next} }
{ print }
' "$FILE" | awk '
/^const[[:space:]]+M2_TOKEN[[:space:]]*=/ { if (++mt>1){print "// " $0; next} }
{ print }
' > "$FILE.tmp1"

# 2) Kommenter ut duplikate async function m2(...) (behold første forekomst)
awk '
/^[[:space:]]*async[[:space:]]+function[[:space:]]+m2[[:space:]]*\(/{
  if (++m2c>1){ in_m2=1; print "// " $0; next }
}
in_m2 && /^\}/ { in_m2=0; print "// " $0; next }
in_m2 { print "// " $0; next }
{ print }
' "$FILE.tmp1" > "$FILE.tmp2"

# 3) Sørg for at det finnes kun én POST-handler
#    Kommenter ut evt. POST nr. 2 og utover.
awk '
/export[[:space:]]+async[[:space:]]+function[[:space:]]+POST[[:space:]]*\(/{
  if (++pc>1){ in_post=1; print "// " $0; next }
}
in_post && /^\}/ { in_post=0; print "// " $0; next }
in_post { print "// " $0; next }
{ print }
' "$FILE.tmp2" > "$FILE.tmp3"

# 4) Sørg for at NextResponse er importert (og bare én gang)
grep -v "from '\''next/server'\''" "$FILE.tmp3" > "$FILE.tmp4"
awk '
BEGIN{done=0}
{
  if (!done && $0 !~ /^import /) {
    print "import { NextResponse } from '\''next/server'\'';"
    done=1
  }
  print
}
' "$FILE.tmp4" > "$FILE"

rm -f "$FILE.tmp1" "$FILE.tmp2" "$FILE.tmp3" "$FILE.tmp4"

echo "→ Rydder .next-cache"
rm -rf .next .next-cache 2>/dev/null || true
echo "✓ Ferdig. Start dev på nytt (npm run dev)."
