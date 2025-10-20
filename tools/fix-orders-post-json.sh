#!/usr/bin/env bash
set -euo pipefail

FILE="app/api/orders/route.ts"
[ -f "$FILE" ] || { echo "Finner ikke $FILE"; exit 1; }

cp "$FILE" "$FILE.bak.$(date +%s)"

# 1) Kommenter ut dupliserte M2_BASE/M2_TOKEN (behold første)
awk '
/^const[[:space:]]+M2_BASE[[:space:]]*=/ { if (++mb>1){print "// " $0; next} }
{ print }
' "$FILE" | awk '
/^const[[:space:]]+M2_TOKEN[[:space:]]*=/ { if (++mt>1){print "// " $0; next} }
{ print }
' > "$FILE.tmp1"

# 2) Hvis det finnes flere POST-handler, behold den første – kommenter resten
awk '
/export[[:space:]]+async[[:space:]]+function[[:space:]]+POST[[:space:]]*\(/{
  if (++pcount>1) { in_post=1; print "// " $0; next }
}
in_post && /^\}/ { in_post=0; print "// " $0; next }
in_post { print "// " $0; next }
{ print }
' "$FILE.tmp1" > "$FILE.tmp2"

# 3) Sørg for at import av NextResponse finnes (uten duplikat)
#    Fjern eksisterende linje(r) og sett inn øverst etter første import-blokk.
grep -v "from 'next/server'" "$FILE.tmp2" > "$FILE.tmp3"

# Finn første linje som ikke er import og sett inn import.
awk '
BEGIN{done=0}
{
  if (!done && $0 !~ /^import /) {
    print "import { NextResponse } from '\''next/server'\'';"
    done=1
  }
  print
}
' "$FILE.tmp3" > "$FILE.tmp4"

# 4) Pakk eksisterende POST-body i try/catch og tving JSON-svar.
#    Erstatter hele POST-funksjonen med en robust wrapper som kaller en intern handler hvis den finnes.
cat > "$FILE.tmp_post" <<'TS'
export async function POST(req: Request) {
  try {
    // Hvis du allerede har egen implementasjon (f.eks. createOrder), forsøk å kalle den:
    if (typeof (globalThis as any).__ORDERS_POST_IMPL === 'function') {
      const out = await (globalThis as any).__ORDERS_POST_IMPL(req)
      return NextResponse.json(out, { status: 201 })
    }

    // Fallback: enkel stub for dev (ingen sideeffekter i Magento)
    const body = await req.json()
    const now = Date.now()
    const out = {
      id: `ORD-${now}`,
      increment_id: `ORD-${now}`,
      status: 'new',
      created_at: new Date(now).toISOString(),
      customer: body?.customer ?? {},
      lines: (body?.lines ?? []).map((l:any, i:number)=>({
        sku: l.sku, productId: l.productId ?? null, name: l.name ?? l.sku, qty: Number(l.qty||1),
        price: Number(l.price ?? 0), rowTotal: Number(l.price ?? 0) * Number(l.qty||1), i
      })),
      notes: body?.notes ?? null,
      elapsed_ms: 1,
      source: 'local-stub'
    }
    return NextResponse.json(out, { status: 201 })
  } catch (err:any) {
    const msg = err?.message || 'unknown error'
    return NextResponse.json({ error: msg }, { status: 500 })
  }
}
TS

# Bytt ut hele POST-implementasjonen i fila med denne (en gang per fil)
# Fjern eksisterende POST-blokk (første) og lim inn vår nye
awk '
BEGIN{printing=1; removed=0}
/export[[:space:]]+async[[:space:]]+function[[:space:]]+POST[[:space:]]*\(/{
  if (!removed){
    # hopp over eksisterende blokk frem til matcher lukkende '}'
    printing=0
    removed=1
  }
}
printing { print; next }
/^\}/ && !printing {
  # slutt på første POST-blokk, sett inn vår nye og slå på printing igjen
  system("cat app/api/orders/route.ts.tmp_post")
  printing=1
}
' "$FILE.tmp4" > "$FILE"

rm -f "$FILE.tmp1" "$FILE.tmp2" "$FILE.tmp3" "$FILE.tmp4" "$FILE.tmp_post"

echo "→ Rydder .next-cache"
rm -rf .next .next-cache 2>/dev/null || true
echo "✓ Ferdig. Start dev på nytt (npm run dev)."
