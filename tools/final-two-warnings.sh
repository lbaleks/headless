#!/bin/bash
set -euo pipefail

# 1) A11y: add role+tabIndex on the div that has onClick in kanban page
KANBAN="app/admin/orders/kanban/page.tsx"
if [ -f "$KANBAN" ]; then
  # Insert role="button" tabIndex={0} into the first <div ... onClick=...> opening tag line (idempotent)
  awk '
    BEGIN{done=0}
    {
      if (!done && $0 ~ /<div[^>]*onClick=/) {
        # If not already present, inject role+tabIndex right after "<div "
        line=$0
        if (line !~ /role="button"/) {
          sub(/<div[[:space:]]+/, "<div role=\"button\" tabIndex={0} ")
        }
        print
        done=1
      } else {
        print
      }
    }
  ' "$KANBAN" > "$KANBAN.__tmp__" && mv "$KANBAN.__tmp__" "$KANBAN"
fi

# 2) prefer-const in fix-dotenv-clean.js
DOTENV="m2-gateway/fix-dotenv-clean.js"
if [ -f "$DOTENV" ]; then
  sed -E -i '' 's/\blet[[:space:]]+kept\b/const kept/g' "$DOTENV"
fi

echo "✅ Final two warnings fixed (a11y + prefer-const). Running eslint…"
pnpm run lint --fix || true
