#!/usr/bin/env bash
set -euo pipefail
f="category-sync.sh"
[ -f "$f" ] || { echo "❌ $f not found"; exit 1; }

# Fix the missing $a + $b in the "attach" merge step
perl -0777 -pe '
  s/
    (jq\s+-c\s+--argjson\s+a\s+"\\$curr"\s+--argjson\s+b\s+"\\$target"\s+)
    '\''\(\s*\+\s*\)\s*\|\s*unique\s*\|\s*map\(tonumber\)\s*\|\s*unique'\''/
    ${1}'"'"'(\$a + \$b) | unique | map(tonumber) | unique'"'"'/
  gx
' -i "$f"

# Normalize line endings & ensure executable
perl -pi -e 's/\r$//' "$f"
chmod +x "$f"
echo "✅ Patched $f (merge uses (\$a + \$b))."
