#!/bin/sh
set -eu
F="src/components/JobsFooter.tsx"
[ -f "$F" ] || { echo "skip: $F (not found)"; exit 0; }

# Flytt "use client" til topp
awk '
  BEGIN { n=0 }
  {
    if ($0 ~ /^[[:space:]]*["'"'"']use client["'"'"'];?[[:space:]]*$/) next;
    lines[++n] = $0
  }
  END {
    print "\"use client\";";
    for (i = 1; i <= n; i++) print lines[i];
  }
' "$F" > "$F.tmp" && mv "$F.tmp" "$F"

echo "✅ JobsFooter fixed."
