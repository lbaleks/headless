#!/bin/sh
set -eu

should_fix() {
  f="$1"
  # inneholder "use client" OG den står ikke øverst
  grep -q '"use client"' "$f" || return 1
  head -n 5 "$f" | grep -q '"use client"' && head -n1 "$f" | grep -q '"use client"' && return 1 || true
  return 0
}

fix_one () {
  f="$1"
  [ -f "$f" ] || return 0
  should_fix "$f" || { echo "skip: $f"; return 0; }

  awk '
    BEGIN { n=0 }
    {
      if ($0 ~ /^[[:space:]]*["'"'"']use client["'"'"'];?[[:space:]]*$/) next;
      lines[++n]=$0
    }
    END {
      print "\"use client\";";
      for (i=1;i<=n;i++) print lines[i];
    }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  echo "✓ fixed: $f"
}

# bare våre mapper – IKKE node_modules/.next/.git
find app src components pages \
  -type f \( -name "*.tsx" -o -name "*.ts" -o -name "*.jsx" -o -name "*.js" \) 2>/dev/null \
| while read -r f; do fix_one "$f"; done

echo "✅ use-client fixed (safe)."
