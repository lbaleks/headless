#!/usr/bin/env bash
set -euo pipefail

echo "🛠 Fikser Next15 params + duplisert NOW …"

# ---------- 1) PRODUCTS GET route: await ctx.params ----------
ROUTE="app/api/products/[sku]/route.ts"
if [ -f "$ROUTE" ]; then
  # a) Sørg for Promise-params i signatur
  perl -0777 -i -pe 's/\{\s*params\s*:\s*\{\s*sku\s*:\s*string\s*\}\s*\}/\{ params: Promise<{ sku: string }> \}/g' "$ROUTE"

  # b) Bytt lesing av sku til await + destrukturering
  perl -0777 -i -pe 's/const\s+sku\s*=\s*ctx\??\.params\??\.sku\s*;/const { sku } = await ctx.params;/g' "$ROUTE"

  # c) Som sikkerhetsnett: dersom filen fortsatt inneholder ctx?.params?.sku, bytt *alle* til await-variant
  perl -0777 -i -pe 's/ctx\??\.params\??\.sku/(await ctx.params).sku/g' "$ROUTE"

  # d) Sørg for at GET er async
  perl -0777 -i -pe 's/\bexport\s+function\s+GET\b/export async function GET/g' "$ROUTE"
fi

# ---------- 2) CUSTOMERS DETAIL: fjern dupliserte NOW & sett korrekt ----------
CUST="app/admin/customers/[id]/page.tsx"
if [ -f "$CUST" ]; then
  # a) Fjern alle feilaktige linjer "const NOW = NOW;"
  perl -0777 -i -pe 's/^\s*const\s+NOW\s*=\s*NOW\s*;\s*\n//mg' "$CUST"

  # b) Normaliser: gjør alle varianter av "const NOW = Date.now();" til samme og behold kun første
  perl -0777 -i -pe 'my $c=0; s/^\s*const\s+NOW\s*=\s*Date\.now\(\)\s*;\s*\n/($c++ ? "" : "const NOW = Date.now();\n")/meg' "$CUST"

  # c) Hvis NOW ikke finnes lenger, sett én korrekt rett etter import-blokken / "use client"
  if ! grep -q 'const NOW = Date\.now();' "$CUST"; then
    # Finn siste import/use client-linje og injiser etter den
    awk '
      BEGIN{inserted=0}
      {
        print $0
        if(!inserted && $0 ~ /^(\s*import\b|["'\'' ]use client["'\'' ]\s*;?\s*)$/){ last=NR }
      }
      END{
        # Etter awk kjører vi et sed-innstikk; enklere å gjøre i ett renn seinere
      }
    ' "$CUST" > "$CUST.tmp"

    # Sett inn etter siste import/"use client" linje
    line=$(grep -nE '^\s*(import\b|("use client"|'\''use client'\''))' "$CUST" | tail -1 | cut -d: -f1 || true)
    if [ -n "${line:-}" ]; then
      # BSD sed insert
      sed -i '' "$((line+1))i\\
const NOW = Date.now();\\
" "$CUST"
    else
      # Ingen imports funnet – legg på toppen
      sed -i '' '1s#^#const NOW = Date.now();\
#' "$CUST"
    fi
    rm -f "$CUST.tmp" 2>/dev/null || true
  fi
fi

echo "✅ Ferdig. Restart dev (eller refresh siden)."
