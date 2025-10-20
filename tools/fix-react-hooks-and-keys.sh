# ---- save as: tools/fix-react-hooks-and-keys.sh ----
#!/bin/sh
set -eu

fix_hooks_file () {
  F="$1"
  [ -f "$F" ] || { echo "skip: $F (not found)"; return 0; }

  # 1) Ensure "use client" is the very first line
  if ! head -n1 "$F" | grep -q '"use client"'; then
    ( printf '"use client";\n' ; cat "$F" ) > "$F.tmp" && mv "$F.tmp" "$F"
    echo "➕ added \"use client\" to top of $F"
  fi

  # 2) Ensure we import React and hooks (add a separate hooks import if missing)
  if ! grep -q "from 'react'" "$F"; then
    # No react import at all – add full import just under "use client"
    sed -i '' '1,/^"use client";/!b; /"use client";/a\
import React, { useEffect, useState } from '\''react'\'';
' "$F"
    echo "➕ added React + hooks import to $F"
  else
    # There is some react import; make sure we have named hooks imported too
    if ! grep -q "useState" "$F"; then
      sed -i '' '1,/^"use client";/!b; /"use client";/a\
import { useEffect, useState } from '\''react'\'';
' "$F"
      echo "➕ added hooks import to $F"
    fi
  fi
}

# --- Fix products page (useState undefined) ---
fix_hooks_file "app/admin/products/page.tsx"

# Make sure Link import is at the top too (harmless if it already exists)
if [ -f "app/admin/products/page.tsx" ] && ! grep -q "from 'next/link'" app/admin/products/page.tsx; then
  sed -i '' '1,/^"use client";/!b; /"use client";/a\
import Link from '\''next/link'\'';
' app/admin/products/page.tsx
  echo "➕ added Link import to app/admin/products/page.tsx"
fi

# --- Fix DockBar (useState/useEffect undefined earlier) ---
fix_hooks_file "src/components/DockBar.tsx"

# --- Fix JobsFooter: "use client" must be before any other code ---
if [ -f "src/components/JobsFooter.tsx" ]; then
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
  ' src/components/JobsFooter.tsx > src/components/JobsFooter.tsx.tmp \
  && mv src/components/JobsFooter.tsx.tmp src/components/JobsFooter.tsx
  echo "✓ fixed: src/components/JobsFooter.tsx (use client on top)"
fi

# --- Fix duplicate key warning in customers table ---
if [ -f "app/admin/customers/page.tsx" ]; then
  # Make the key stable AND unique by appending the index
  # from: <tr key={(c.id ?? c.email ?? String(i))}
  #   to: <tr key={`${c.id ?? c.email ?? String(i)}-${i}`}
  sed -E -i '' 's#<tr key=\{\(c\.id \?\? c\.email \?\? String\(i\)\)\}#<tr key={`\${c.id ?? c.email ?? String(i)}-\${i}`}#' app/admin/customers/page.tsx || true
  echo "✓ fixed: duplicate key in app/admin/customers/page.tsx"
fi

echo "✅ Hooks + keys patched. Restarting dev server is recommended."