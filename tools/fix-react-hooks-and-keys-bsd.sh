# tools/fix-react-hooks-and-keys-bsd.sh
#!/bin/sh
set -eu

fix_hooks_file () {
  F="$1"
  [ -f "$F" ] || { echo "skip: $F (not found)"; return 0; }

  # 1) Ensure "use client" is the very first line
  perl -0777 -i -pe '
    # remove any existing "use client" lines
    s/^[ \t]*["\x27]use client["\x27];?[ \t]*\r?\n//mg;
    # prepend it
    $_ = qq{"use client";\n} . $_;
  ' "$F"

  # 2) If there is no react import at all, add full import under directive
  perl -0777 -i -pe '
    unless ( /from \x27react\x27/ or /from "react"/ ) {
      s/\A("use client";\s*\r?\n)/$1import React, { useEffect, useState } from '\''react'\'';\n/s;
    }
  ' "$F"

  # 3) If react import exists but hooks are missing, add a named hooks import
  perl -0777 -i -pe '
    if ( /from \x27react\x27|from "react"/ && $_ !~ /\buseState\b/ ) {
      s/\A("use client";\s*\r?\n)/$1import { useEffect, useState } from '\''react'\'';\n/s;
    }
  ' "$F"
}

# --- Fix Products page (useState undefined) ---
fix_hooks_file "app/admin/products/page.tsx"

# Ensure Link import exists (safe if duplicated – this adds it only if missing)
if [ -f "app/admin/products/page.tsx" ]; then
  perl -0777 -i -pe '
    if ( $_ !~ /from \x27next\/link\x27|from "next\/link"/ ) {
      s/\A("use client";\s*\r?\n)/$1import Link from '\''next\/link'\'';\n/s;
    }
  ' app/admin/products/page.tsx
fi

# --- Fix DockBar (useState/useEffect undefined) ---
fix_hooks_file "src/components/DockBar.tsx"

# --- Fix JobsFooter: "use client" MUST be first ---
if [ -f "src/components/JobsFooter.tsx" ]; then
  perl -0777 -i -pe '
    s/^[ \t]*["\x27]use client["\x27];?[ \t]*\r?\n//mg;
    $_ = qq{"use client";\n} . $_;
  ' src/components/JobsFooter.tsx
  echo "✓ fixed: src/components/JobsFooter.tsx (use client on top)"
fi

# --- Fix duplicate key warning in customers table ---
if [ -f "app/admin/customers/page.tsx" ]; then
  perl -0777 -i -pe '
    s#<tr key=\{\(c\.id \?\? c\.email \?\? String\(i\)\)\}#<tr key={`\${c.id ?? c.email ?? String(i)}-\${i}`}#g;
  ' app/admin/customers/page.tsx
  echo "✓ fixed: duplicate key in app/admin/customers/page.tsx"
fi

echo "✅ Hooks + keys patched. Restarting dev server is recommended."