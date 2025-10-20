#!/bin/bash
set -euo pipefail

# --- 1) A11y fix: add role/tabIndex/onKeyDown to the first <div ... onClick=...>
KANBAN="app/admin/orders/kanban/page.tsx"
if [ -f "$KANBAN" ]; then
  perl -0777 -i -pe '
    my $done=0;
    s{
      <div                             # opening div
      (                                # capture attrs
        (?:
          (?!>)                        # not the end of tag
          .                            # any char
        )*?
        \bonClick=                     # has onClick somewhere in attrs
        (?:
          (?!>)
          .
        )*?
      )
      >                                # end of opening tag
    }{
      if($done){ "<div$1>" }           # only touch the first match
      else{
        my $attrs=$1;
        $attrs .= q{ role="button"}         unless $attrs =~ /\brole=/;
        $attrs .= q{ tabIndex={0}}          unless $attrs =~ /\btabIndex=/;
        $attrs .= q{ onKeyDown={(e)=>{if(e.key==="Enter"||e.key===" "){e.preventDefault?.(); e.currentTarget?.click?.();}}}}
                                              unless $attrs =~ /\bonKeyDown=/;
        $done=1;
        "<div$attrs>"
      }
    }sex;
  ' "$KANBAN"
fi

# --- 2) prefer-const: let kept -> const kept (robust for var/spacing)
if [ -f "m2-gateway/fix-dotenv-clean.js" ]; then
  perl -0777 -i -pe 's/\b(?:let|var)\s+kept\b/const kept/g' m2-gateway/fix-dotenv-clean.js
fi

echo "✅ Final autofix applied. Running eslint…"
pnpm run lint --fix || true
