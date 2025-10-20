#!/usr/bin/env bash
set -euo pipefail

F="category-sync.sh"
[ -f "$F" ] || { echo "❌ Fant ikke $F i $(pwd). Kjør fra mappen der filen ligger."; exit 1; }

echo "→ Rydder CR og quarantine…"
perl -pi -e 's/\r$//' "$F" || true
xattr -d com.apple.quarantine "$F" 2>/dev/null || true

echo "→ Patcher jq-uttrykk og case-endelser…"
perl -0777 -i -pe '
  # 1) Feil merge-syntaks som har sneket seg inn (f.eks. [a[], b[]]) → ($a + $b)
  s/\[ \s* a \s* \[\] \s* , \s* b \s* \[\] \s* \]/($a + $b)/gx;

  # 2) Eventuelle varianter som ble forsøkt (eks. ([$a[], $b[])) → ($a + $b)
  s/\(\s*\[\s*\$a\s*\[\]\s*,\s*\$b\s*\[\]\s*\)\s*/($a + $b)/gx;

  # 3) Sørg for at merges ender med | map(tonumber) | unique
  #    (dersom det allerede finnes, lar vi det stå urørt)
  s/\(\$a \+ \$b\)(?![^\n]*map\s*\(\s*tonumber\s*\)\s*\|\s*unique)/($a + $b | map(tonumber) | unique)/g;

  # 4) a==b → ($a|sort)==($b|sort)  (likhetssjekk på sorterte lister)
  s/\ba==b\b/($a|sort)==($b|sort)/g;

  # 5) endac → esac  (case/end-blunder)
  s/\bendac\b/esac/g;
' "$F"

echo "→ Setter execute-bit og syntaks-sjekker…"
chmod +x "$F"
bash -n "$F"

echo "✅ $F patchet og klar."
echo
echo "Bruk:"
cat <<'HINT'
  # bevarer eksisterende – legger bare til manglende
  ./category-sync.sh --file categories.csv --mode attach

  # eksakt match – erstatter eksisterende
  ./category-sync.sh --file categories.csv --mode replace

  # tørrkjør
  ./category-sync.sh --file categories.csv --mode replace --dry-run
HINT
