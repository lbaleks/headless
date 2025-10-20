#!/bin/bash
set -euo pipefail

# --- 1) A11y på kanban: legg til role, tabIndex og onKeyDown på <div ... onClick=...> ---
KANBAN="app/admin/orders/kanban/page.tsx"
if [ -f "$KANBAN" ]; then
  perl -0777 -i -pe '
    s{
      <div([^>]*onClick=[^>]*)(>)
    }{
      my $attrs = $1;
      my $end   = $2;

      $attrs .= qq{ role="button"}                           unless $attrs =~ /\brole=/;
      $attrs .= qq{ tabIndex={0}}                            unless $attrs =~ /\btabIndex=/;
      $attrs .= qq{ onKeyDown={(e)=>{if(e.key==="Enter"||e.key===" "){e.preventDefault?.(); e.currentTarget?.click?.();}}}}
                                                           unless $attrs =~ /\bonKeyDown=/;

      "<div$attrs$end"
    }egx;
  ' "$KANBAN"
fi

# --- 2) prefer-const: let kept -> const kept ---
if [ -f "m2-gateway/fix-dotenv-clean.js" ]; then
  perl -0777 -i -pe 's/\blet\s+kept\b/const kept/g' m2-gateway/fix-dotenv-clean.js
fi

echo "✅ Final cleanup done. Running eslint…"
pnpm run lint --fix || true
