#!/bin/sh
set -eu

F="src/components/DockBar.tsx"
[ -f "$F" ] || { echo "skip: $F (not found)"; exit 0; }

# 1) sørg for "use client" øverst
if ! head -n1 "$F" | grep -q '"use client"'; then
  awk '
    BEGIN{n=0}
    {
      if ($0 ~ /^[[:space:]]*["'"'"']use client["'"'"'];?[[:space:]]*$/) next;
      lines[++n]=$0
    }
    END{
      print "\"use client\";";
      for(i=1;i<=n;i++) print lines[i];
    }
  ' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
fi

# 2) hooks-import
if grep -q 'import \* as React from *'\''react'\''' "$F"; then
  # har "import * as React from 'react'" – legg til named hooks separat hvis mangler
  grep -q 'from '\''react'\''.*useState' "$F" || \
    sed -i '' '1,/^$/ s#^#import { useState, useEffect } from '\''react'\'';\n#' "$F"
elif grep -q 'import React' "$F"; then
  # har default React – fold inn hooks på samme linje om de ikke finnes
  perl -0777 -i -pe "s/(import\s+React\s*(?:,\s*\{[^}]*\})?\s*from\s*'react'\s*;?)/do{ my \$x=\$1; \$x=~s/import\s+React\s*from/import React, { useState, useEffect } from/ unless \$x=~/useState|useEffect/; \$x }/ge" "$F"
else
  # ingen react-import – legg til full import øverst (etter 'use client')
  sed -i '' '1,/^"use client";/!b; /"use client";/a\
import React, { useState, useEffect } from '\''react'\'';
' "$F"
fi

echo "✅ DockBar hooks fixed."
