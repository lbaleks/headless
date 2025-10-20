#!/usr/bin/env bash
set -euo pipefail

F="category-sync.sh"
[ -f "$F" ] || { echo "❌ Fant ikke $F i $(pwd). Kjør skriptet fra samme mappe som $F."; exit 1; }

echo "→ Rydder linjeendelser og quarantine…"
perl -pi -e 's/\r$//' "$F" || true
xattr -d com.apple.quarantine "$F" 2>/dev/null || true

echo "→ Patcher jq-merge + likhetssjekk + evt. endac…"
# Multilinje-safe patch med perl
perl -0777 -i -pe '
  # 1) Feil merge ([a[], b[]] …) → korrekt union med variabler ($a + $b | …)
  s/
    jq \s* -c \s* --argjson \s* a \s* "\$curr" \s* --argjson \s* b \s* "\$target" \s*
    (?:'"'"'[^'"'"']*'"'"'|[^'\n]*)           # hva som enn stod som jq-program
  /jq -c --argjson a "$curr" --argjson b "$target" '\''
($a + $b | map(tonumber) | unique)
'\''/xms;

  # 2) a==b → ($a|sort)==($b|sort)
  s/\ba==b\b/($a|sort)==($b|sort)/g;

  # 3) Sikre case-slutt
  s/\bendac\b/esac/g;
' "$F"

echo "→ Sørger for execute-bit…"
chmod +x "$F"

echo "→ Hurtig syntaks-sjekk…"
bash -n "$F"

echo "✅ $F patchet og klar."

# Bonus: kort bruksinfo
cat <<'HINT'

Bruk:
  # bevarer eksisterende – legger bare til manglende
  ./category-sync.sh --file categories.csv --mode attach

  # eksakt match – erstatter eksisterende
  ./category-sync.sh --file categories.csv --mode replace

  # tørrkjør
  ./category-sync.sh --file categories.csv --mode replace --dry-run
HINT
