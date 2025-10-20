#!/bin/sh
set -eu

FILE="src/components/DockBar.tsx"
[ -f "$FILE" ] || { echo "Fant ikke $FILE"; exit 0; }

awk '
  BEGIN { n = 0 }
  {
    # Fjern tilfeldige "use client" og gamle react-importer – vi legger inn rene varianter
    if ($0 ~ /^[[:space:]]*["'"'"']use client["'"'"'];[[:space:]]*$/) next
    if ($0 ~ /^[[:space:]]*import[[:space:]].*from[[:space:]]*["'"'"']react["'"'"'];?[[:space:]]*$/) next
    lines[++n] = $0
  }
  END {
    print "\"use client\";";
    print "import React, { useState, useEffect } from \"react\";";
    for (i = 1; i <= n; i++) print lines[i];
  }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

echo "✅ Patchet $FILE (useState + useEffect)"
