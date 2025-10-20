#!/usr/bin/env bash
set -euo pipefail

# What to scan (adjust as needed)
ROOTS=("app" "src")

# File extensions to check
ext_regex='.*\.(ts|tsx|js|jsx)$'

echo "→ guard-imports: scanning for misplaced imports…"

exitcode=0

# Find files and check each with awk
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  # Use -print0 to handle spaces, loop with read -r -d '' (Bash-safe)
  while IFS= read -r -d '' f; do
    awk -v fname="$f" '
      BEGIN {
        inImports = 1       # we start at the top import section
      }
      # blank lines are fine anywhere
      /^[[:space:]]*$/ { next }

      # line comments are fine
      /^[[:space:]]*\/\// { next }

      # full import lines
      /^[[:space:]]*import[[:space:]].*from[[:space:]].*;[[:space:]]*$/ {
        if (inImports) {
          next
        } else {
          # import after code has started
          printf("%s:%d: late import not allowed here: %s\n", fname, NR, $0) > "/dev/stderr"
          bad = 1
          next
        }
      }

      {
        # code has started; any further import lines are "late"
        inImports = 0

        # flag inline imports of Link specifically (the bad pattern you hit)
        if ($0 ~ /import[[:space:]]+Link[[:space:]]+from[[:space:]]+["'\'']next\/link["'\'']/) {
          printf("%s:%d: inline import of Link detected (move to top): %s\n", fname, NR, $0) > "/dev/stderr"
          bad = 1
        }
      }

      END {
        if (bad) exit 2
      }
    ' "$f" || exitcode=$((exitcode|1))
  done < <(find "$root" -type f -regex "$ext_regex" -print0)
done

if [ "$exitcode" -ne 0 ]; then
  echo "✗ guard-imports failed. Fix the lines above." >&2
  exit "$exitcode"
fi

echo "✓ guard-imports OK"
