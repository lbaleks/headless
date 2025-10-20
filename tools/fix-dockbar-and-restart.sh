#!/bin/bash
set -euo pipefail

FILE="src/components/DockBar.tsx"

if [[ -f "$FILE" ]]; then
  echo "🔧 Fikser React-hook imports i $FILE"

  # Sørg for at 'use client' ligger helt øverst (uten å duplisere)
  awk '
    BEGIN { has=0; n=0 }
    /^'\''use client'\'';\s*$/ || /^"use client";\s*$/ { has=1; next }
    { lines[n++]=$0 }
    END {
      if (has) print "\"use client\";";
      for (i=0;i<n;i++) print lines[i];
    }
  ' "$FILE" > "$FILE.__tmp" && mv "$FILE.__tmp" "$FILE"

  # 1) Dersom fila importerer "* as React", bytt til default + named
  if grep -qE '^import \* as React from '\''react'\'';' "$FILE"; then
    sed -E -i '' "s|^import \* as React from 'react';|import React, { useState, useEffect, useMemo, useRef, useCallback, useTransition, useOptimistic } from 'react';|" "$FILE"
  fi

  # 2) Hvis det ikke finnes noen import fra react (hverken default eller *), sett inn etter 'use client'
  if ! grep -qE "^import .* from 'react';" "$FILE"; then
    # Sett inn rett etter første linje
    sed -i '' '1{
      N
      s#^("use client";\n)#\1import React, { useState, useEffect, useMemo, useRef, useCallback, useTransition, useOptimistic } from '\''react'\'';\n#
    }' "$FILE"
  fi

  # 3) Hvis koden bruker React.useState, legg også til en named import for useState (ufarlig om allerede finnes)
  if grep -q 'React\.useState' "$FILE"; then
    # Sørg for at { useState } er nevnt i importen
    perl -0777 -i -pe "s|(import\s+React,\s*\{)([^}]*)\}|my \$pre=\$1; my \$inside=\$2; \$inside=~s/\buseState\b//; \$inside=~s/^\s*,\s*//; \$inside=~s/\s*,\s*\$//; \$inside=~s/\s+/, /g; \$inside=\$inside ? \"\$inside, useState\" : \"useState\"; \"\${pre}\$inside}\"|e" "$FILE"
  fi
else
  echo "ℹ️ Fant ikke $FILE – hopper over."
fi

echo "🧹 Rydder Next-cache (.next)"
rm -rf .next || true

echo "🚀 Starter Next dev på nytt…"
pnpm dev
