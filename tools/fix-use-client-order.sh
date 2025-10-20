#!/bin/sh
set -eu

fix_one () {
  f="$1"
  [ -f "$f" ] || return 0

  # Flytt evt. eksisterende "use client" til topp (som første statement)
  awk '
    BEGIN { n = 0 }
    {
      # dropp alle eksisterende "use client"-linjer (vi legger inn én på topp)
      if ($0 ~ /^[[:space:]]*["'"'"']use client["'"'"'];?[[:space:]]*$/) next;
      lines[++n] = $0
    }
    END {
      print "\"use client\";";
      for (i = 1; i <= n; i++) print lines[i];
    }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  echo "✓ fixed: $f"
}

# 1) Fiks JobsFooter direkte
[ -f "src/components/JobsFooter.tsx" ] && fix_one "src/components/JobsFooter.tsx"

# 2) Fiks alle .tsx/.ts/.jsx/.js som inneholder "use client" men ikke øverst
#    (trygt: vi flytter bare direktivet til førstelinje)
find . \( -name "*.tsx" -o -name "*.ts" -o -name "*.jsx" -o -name "*.js" \) \
  -type f -print0 | xargs -0 grep -l '"use client"' | while read -r file; do
  fix_one "$file"
done

echo "✅ \"use client\" flyttet til toppen der det trengtes."
