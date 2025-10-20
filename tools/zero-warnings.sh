#!/bin/bash
set -euo pipefail

# --- 1) Bytt første <div ... onClick=...> til <button type="button" ...> i Kanban ---
KANBAN="app/admin/orders/kanban/page.tsx"
if [ -f "$KANBAN" ]; then
  perl -0777 -i -pe '
    my $done=0;
    s{
      <div                             # åpningstag
      (                                # $1 = attributter (inkl. onClick et sted)
        (?:
          (?!>) .                      # alt frem til >
        )*?
        \bonClick=
        (?:
          (?!>) .
        )*?
      )
      >                                # slutt på åpningstag
      (.*?)                            # $2 = innhold frem til første </div>
      </div>
    }{
      if ($done) {
        "<div$1>$2</div>"
      } else {
        $done = 1;
        my $attrs = $1;

        # Sørg for at class -> className i attributter
        $attrs =~ s/\bclass="/className="/g;

        # Legg til type, role, tabIndex og onKeyDown dersom mangler
        $attrs .= q{ type="button"} unless $attrs =~ /\btype=/;
        $attrs .= q{ role="button"} unless $attrs =~ /\brole=/;
        $attrs .= q{ tabIndex={0}}  unless $attrs =~ /\btabIndex=/;
        $attrs .= q{ onKeyDown={(e)=>{if(e.key==="Enter"||e.key===" "){e.preventDefault?.(); e.currentTarget?.click?.();}}}}
          unless $attrs =~ /\bonKeyDown=/;

        "<button$attrs>$2</button>"
      }
    }sex;
  ' "$KANBAN" || true
fi

# --- 2) prefer-const: let/var kept -> const kept ---
if [ -f "m2-gateway/fix-dotenv-clean.js" ]; then
  perl -0777 -i -pe 's/\b(?:let|var)\s+kept\b/const kept/g' m2-gateway/fix-dotenv-clean.js
fi

echo "✅ Zero-warnings-fix applied. Running eslint…"
pnpm run lint --fix || true
