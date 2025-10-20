#!/usr/bin/env bash
set -euo pipefail
f="category-sync.sh"
[ -f "$f" ] || { echo "❌ $f not found"; exit 1; }

# 1) Fix equality check: '(|sort)==(|sort)'  ->  '($a|sort)==($b|sort)'
perl -0777 -pe \
's/jq -nc --argjson a ([^\n]+?) --argjson b ([^\n]+?) *'\''\(\|sort\)==\(\|sort\)'\''/jq -nc --argjson a $1 --argjson b $2 '"'"'(\$a|sort)==(\$b|sort)'"'"'/g' \
-i "$f"

# 2) Fix merge: '( + ) | unique | map(tonumber) | unique'  ->  '($a + $b) | unique | map(tonumber) | unique'
perl -0777 -pe \
's/jq -c --argjson a "\\$curr" --argjson b "\\$target" *'\''\(\s*\+\s*\)\s*\|\s*unique\s*\|\s*map\(tonumber\)\s*\|\s*unique'\''/jq -c --argjson a "\$curr" --argjson b "\$target" '"'"'(\$a + \$b) | unique | map(tonumber) | unique'"'"'/g' \
-i "$f"

# 3) Fix any earlier bad merge like '([a[], b[]] | unique ...)'
perl -0777 -pe \
's/\(\[a\[\],\s*b\[\]\]\s*\|\s*unique\)/(\$a + \$b) \| unique/g' \
-i "$f"

# Normalize line endings + ensure executable
perl -pi -e 's/\r$//' "$f"
chmod +x "$f"
echo "✅ Patched $f."
