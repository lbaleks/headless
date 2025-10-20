#!/bin/bash
set -euo pipefail

shopt -s nullglob

FILES=(
  app/**/*.tsx
  src/**/*.tsx
  admstage/**/*.tsx
)

fix_file () {
  local f="$1"
  [ -f "$f" ] || return 0

  # Only TSX files
  [[ "$f" != *.tsx ]] && return 0

  echo "🔧 Fixing $f"

  # 1) Pull out optional "use client"; and all import lines.
  awk '
    BEGIN{ hasUseClient=0 }
    NR==1 && $0 ~ /^"use client";\s*$/ { hasUseClient=1; print $0 > "/tmp/__useclient"; next }
    $0 ~ /^import[[:space:]].*from[[:space:]]+[\"\047].*[\"\047];?[[:space:]]*$/ { print $0 >> "/tmp/__imports"; next }
    { print $0 >> "/tmp/__rest" }
  ' "$f"

  # 2) Compose new file: "use client"; (if present) + imports + rest
  {
    if [ -s /tmp/__useclient ]; then cat /tmp/__useclient; fi
    if [ -s /tmp/__imports ]; then cat /tmp/__imports; fi
    if [ -s /tmp/__rest ]; then cat /tmp/__rest; fi
  } > "$f.__tmp1"

  rm -f /tmp/__useclient /tmp/__imports /tmp/__rest

  # 3) Ensure hook imports exist if hooks are used
  #    Insert after the first import line block.
  if grep -Eq '\b(React\.useState|React\.useEffect|useState\(|useEffect\()' "$f.__tmp1"; then
    if ! grep -Eq 'import\s+\{[^}]*useState|useEffect' "$f.__tmp1"; then
      awk '
        BEGIN { inserted=0 }
        {
          if (!inserted && $0 ~ /^import /) {
            print $0
            if ((getline nextline) > 0) {
              print "import { useState, useEffect } from \"react\";"
              print nextline
              inserted=1
            }
          } else {
            print $0
          }
        }
      ' "$f.__tmp1" > "$f.__tmp2"
    else
      cp "$f.__tmp1" "$f.__tmp2"
    fi
  else
    cp "$f.__tmp1" "$f.__tmp2"
  fi
  rm -f "$f.__tmp1"

  # 4) Replace React.useX with hooks, fix stray braces, tidy imports
  perl -0777 -i -pe '
    # React.useX -> useX
    s/\bReact\.useState\b/useState/g;
    s/\bReact\.useEffect\b/useEffect/g;

    # Fix accidental "{"
    s/(useState\s*\([^)]*\))\s*\{/$1;/g;
    s/(useEffect\s*\([^)]*\))\s*\{/$1;/g;

    # Remove unused "import * as React ..." if React. is no longer referenced
  ' "$f.__tmp2"

  # If file no longer contains "React.", drop the star import
  if ! grep -q 'React\.' "$f.__tmp2"; then
    sed -E -i '' '/^import[[:space:]]+\* as React[[:space:]]+from[[:space:]]+["'\'']react["'\''];?[[:space:]]*$/d' "$f.__tmp2"
  fi

  mv "$f.__tmp2" "$f"
}

for pattern in "${FILES[@]}"; do
  for file in $pattern; do
    fix_file "$file"
  done
done

echo "✅ Hooks + import layout fixed. Restarting dev server…"
killall -9 node 2>/dev/null || true
pnpm dev
